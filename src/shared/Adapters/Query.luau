--!strict
--[[
    Unrest / Adapters / Query

    The selector engine behind `Unrest:Query`.

    A query is *live*, not a one-shot scan -- that is what the whiteboard's arrow into
    CollectionService means. Two sets are maintained:

      * watched  -- every candidate the source can produce (everything carrying the tag, or
                    everything in the ancestor subtree). Each watched instance keeps a small
                    maid holding a `Destroying` connection plus exactly the property and
                    attribute connections this descriptor actually needs: a `Name` or `Role`
                    filter earns a `Name` watch, a `Role` or `Group` filter earns an
                    attribute watch, and a class-only filter earns neither.
      * bindings -- the subset that currently matches. Each keeps a maid holding the event
                    connections the adapter created for the handler table.

    An instance can therefore join and leave the result set any number of times over its
    lifetime, and `Removed` fires exactly once per departure.

    What a handler is allowed to be is not decided here. Query asks the AdapterRegistry to
    attach the table, and the registry raises if the element's class cannot honour it -- so
    "a Frame cannot Submit" is one rule in one place, whether the handler arrived from Luau
    or from an `UnrestCommand` attribute.
]]

local CollectionService = game:GetService("CollectionService")

local Adapters = require(script.Parent)
local Constants = require(script.Parent.Parent.Constants)
local Maid = require(script.Parent.Parent.Util.Maid)
local Resolver = require(script.Parent.Parent.Util.Resolver)
local Selector = require(script.Parent.Selector)
local Signal = require(script.Parent.Parent.Util.Signal)
local Types = require(script.Parent.Parent.Types)

local Query = {}

--[[
    Creates a live query. `handlers` is optional -- a bare query is still useful for
    `:Elements()` / `:Each()` / the ElementAdded and ElementRemoved signals.

    The handle owns its own lifetime: nothing else holds a reference to it, so a query that
    outlives its screen must be `:Destroy()`ed by whoever made it.
]]
function Query.new(
    registry: Types.AdapterRegistry,
    descriptor: Types.Descriptor,
    handlers: Types.Handlers?
): Types.QueryHandle
    local compiled = Selector.parse(descriptor)
    local bound: Types.Handlers = if handlers ~= nil then Resolver.Handlers(handlers) else {}

    local watchedProperties, watchedAttributes = Selector.triggers(compiled)
    local watchesAncestors = Selector.watchesAncestors(compiled)
    local hint = `Narrow the query {compiled.Text} with a Selector or a Role, or drop that handler.`

    local lifetime = Maid.new()
    local watched: { [Instance]: Types.Maid } = {}
    local bindings: { [Instance]: Types.Maid } = {}
    local elements: { Instance } = {}
    local destroyed = false

    local elementAdded: Types.Signal<Instance> = Signal.new("Query.ElementAdded")
    local elementRemoved: Types.Signal<Instance> = Signal.new("Query.ElementRemoved")
    lifetime:Add(elementAdded)
    lifetime:Add(elementRemoved)

    local handle = {
        Selector = compiled,
        ElementAdded = elementAdded,
        ElementRemoved = elementRemoved,
    }
    local typed = (handle :: any) :: Types.QueryHandle

    local function detach(element: Instance): ()
        local binding = bindings[element]
        if binding == nil then
            return
        end

        bindings[element] = nil
        binding:Destroy()

        local index = table.find(elements, element)
        if index ~= nil then
            table.remove(elements, index)
        end

        local removed = bound.Removed
        if removed ~= nil then
            removed(element, nil)
        end
        elementRemoved:Fire(element)
    end

    local function attach(element: Instance): ()
        if bindings[element] ~= nil then
            return
        end

        local binding = Maid.new()
        bindings[element] = binding
        table.insert(elements, element)

        Adapters.bind(registry, element, bound, binding, hint)

        local added = bound.Added
        if added ~= nil then
            added(element, nil)
        end
        elementAdded:Fire(element)
    end

    local function evaluate(element: Instance): ()
        if destroyed then
            return
        end
        if Selector.matches(element, compiled) then
            attach(element)
        else
            detach(element)
        end
    end

    local function unwatch(element: Instance): ()
        local watcher = watched[element]
        if watcher ~= nil then
            watched[element] = nil
            watcher:Destroy()
        end
        detach(element)
    end

    --[[
        A `Group` filter reads through the element to the chain above it, so an edit up there
        moves the element in or out of this set just as surely as an edit on the element
        itself. The whole chain is watched, not only the ancestor supplying a value today: a
        nearer one that sets `UnrestGroup` tomorrow takes precedence the moment it does.

        Rebuilt under a keyed maid slot, so reparenting drops the previous chain outright
        rather than accumulating connections to ancestors the element no longer has.
    ]]
    local function bindAncestry(element: Instance, watcher: Types.Maid): ()
        local chain = Maid.new()
        watcher:Add(chain, "ancestry")

        for _, ancestor in Selector.ancestorChain(element) do
            chain:Add(ancestor:GetAttributeChangedSignal(Constants.Attributes.Group):Connect(function()
                evaluate(element)
            end))
        end
    end

    local function watch(element: Instance): ()
        if destroyed or watched[element] ~= nil then
            return
        end

        local watcher = Maid.new()
        watched[element] = watcher

        -- A rename, or an edit to UnrestRole / UnrestGroup, can move an element in or out.
        for _, property in watchedProperties do
            watcher:Add(element:GetPropertyChangedSignal(property):Connect(function()
                evaluate(element)
            end))
        end
        for _, attribute in watchedAttributes do
            watcher:Add(element:GetAttributeChangedSignal(attribute):Connect(function()
                evaluate(element)
            end))
        end
        if watchesAncestors then
            bindAncestry(element, watcher)

            -- Moving anywhere above the element changes which ancestors it reads from, and
            -- is exactly the set of moves that can change the answer.
            watcher:Add(element.AncestryChanged:Connect(function()
                bindAncestry(element, watcher)
                evaluate(element)
            end))
        end

        watcher:Add(element.Destroying:Connect(function()
            unwatch(element)
        end))

        evaluate(element)
    end

    -- Sourcing: tags win, otherwise the ancestor subtree.
    local tag = compiled.Tag
    if tag ~= nil then
        lifetime:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(watch))
        lifetime:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch))
        for _, element in CollectionService:GetTagged(tag) do
            watch(element)
        end
    else
        local ancestor = compiled.Ancestor :: Instance
        if compiled.Recursive then
            lifetime:Add(ancestor.DescendantAdded:Connect(watch))
            lifetime:Add(ancestor.DescendantRemoving:Connect(unwatch))
            for _, element in ancestor:GetDescendants() do
                watch(element)
            end
        else
            lifetime:Add(ancestor.ChildAdded:Connect(watch))
            lifetime:Add(ancestor.ChildRemoved:Connect(unwatch))
            for _, element in ancestor:GetChildren() do
                watch(element)
            end
        end
    end

    function handle:Elements(): { Instance }
        return table.clone(elements)
    end

    function handle:Count(): number
        return #elements
    end

    function handle:Each(visitor: Types.ElementHandler): Types.QueryHandle
        if type(visitor) ~= "function" then
            error(`[Unrest.Query] :Each expects a function, got {typeof(visitor)}.`, 0)
        end
        for _, element in table.clone(elements) do
            visitor(element, nil)
        end
        return typed
    end

    function handle:Bind(extra: Types.Handlers): Types.QueryHandle
        if destroyed then
            error(`[Unrest.Query] :Bind called on a destroyed query {compiled.Text}.`, 0)
        end

        local validated = Resolver.Handlers(extra)
        local mutable = bound :: { [string]: any }
        for key, value in validated :: { [string]: any } do
            mutable[key] = value
        end

        -- Rebuild every binding so a replaced handler does not leave its predecessor connected.
        for element, binding in bindings do
            binding:Clean()
            Adapters.bind(registry, element, bound, binding, hint)
        end

        return typed
    end

    function handle:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        for element in table.clone(watched) do
            unwatch(element)
        end
        table.clear(watched)
        table.clear(bindings)
        table.clear(elements)

        lifetime:Destroy()
    end

    return typed
end

return Query
