--!strict
--[[
    Unrest / Bridge / Query

    The selector engine behind `Unrest:Query`.

    A query is *live*, not a one-shot scan -- that is what the whiteboard's arrow into
    CollectionService means. Two sets are maintained:

      * watched  -- every candidate the source can produce (everything carrying the tag, or
                    everything in the ancestor subtree). Each watched instance keeps a small
                    maid holding a Destroying connection and, when the descriptor filters on
                    Name, a Name-changed connection so a rename re-runs the predicate.
      * bindings -- the subset that currently matches. Each keeps a maid holding the event
                    connections created for the handler table.

    An instance can therefore join and leave the result set any number of times over its
    lifetime, and `Removed` fires exactly once per departure.
]]

local CollectionService = game:GetService("CollectionService")

local Maid = require(script.Parent.Maid)
local Resolver = require(script.Parent.Resolver)
local Selector = require(script.Parent.Selector)
local Signal = require(script.Parent.Signal)
local Types = require(script.Parent.Parent.Types)

local Query = {}

--[[
    Binding matrix. Anything outside it is a programming error rather than a silent no-op:
    a query that says `Active` but selects Frames is a query with the wrong Selector, and
    saying so loudly at bind time is far cheaper than wondering why nothing clicks.
]]
local function bindHandlers(element: Instance, handlers: Types.Handlers, maid: Types.Maid, text: string): ()
    local active = handlers.Active
    if active ~= nil then
        if element:IsA("GuiButton") then
            local button = element :: GuiButton
            maid:Add(button.Activated:Connect(function()
                active(element)
            end))
        elseif element:IsA("ClickDetector") then
            local detector = element :: ClickDetector
            maid:Add(detector.MouseClick:Connect(function()
                active(element)
            end))
        elseif element:IsA("ProximityPrompt") then
            local prompt = element :: ProximityPrompt
            maid:Add(prompt.Triggered:Connect(function()
                active(element)
            end))
        else
            error(
                `[Unrest.Query] handler "Active" cannot bind to {element:GetFullName()}: a {element.ClassName} `
                    .. `is not a GuiButton, ClickDetector or ProximityPrompt. `
                    .. `Narrow the query {text} with Selector = "TextButton" (or drop the Active handler).`,
                0
            )
        end
    end

    local hover, unhover = handlers.Hover, handlers.Unhover
    if hover ~= nil or unhover ~= nil then
        if element:IsA("GuiObject") then
            local gui = element :: GuiObject
            if hover ~= nil then
                maid:Add(gui.MouseEnter:Connect(function()
                    hover(element)
                end))
            end
            if unhover ~= nil then
                maid:Add(gui.MouseLeave:Connect(function()
                    unhover(element)
                end))
            end
        elseif element:IsA("ClickDetector") then
            local detector = element :: ClickDetector
            if hover ~= nil then
                maid:Add(detector.MouseHoverEnter:Connect(function()
                    hover(element)
                end))
            end
            if unhover ~= nil then
                maid:Add(detector.MouseHoverLeave:Connect(function()
                    unhover(element)
                end))
            end
        else
            local key = if hover ~= nil then "Hover" else "Unhover"
            error(
                `[Unrest.Query] handler "{key}" cannot bind to {element:GetFullName()}: a {element.ClassName} `
                    .. `is not a GuiObject or ClickDetector. Narrow the query {text} with a Selector.`,
                0
            )
        end
    end
end

--[[
    Creates a live query. `handlers` is optional -- a bare query is still useful for
    `:Elements()` / `:Each()` / the ElementAdded and ElementRemoved signals.
]]
function Query.new(descriptor: Types.Descriptor, handlers: Types.Handlers?): Types.QueryHandle
    local compiled = Selector.parse(descriptor)
    local bound: Types.Handlers = if handlers ~= nil then Resolver.Handlers(handlers) else {}

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
            removed(element)
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

        bindHandlers(element, bound, binding, compiled.Text)

        local added = bound.Added
        if added ~= nil then
            added(element)
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

    local function watch(element: Instance): ()
        if destroyed or watched[element] ~= nil then
            return
        end

        local watcher = Maid.new()
        watched[element] = watcher

        -- A rename can move an element in or out of the result set.
        if compiled.Name ~= nil then
            watcher:Add(element:GetPropertyChangedSignal("Name"):Connect(function()
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
            visitor(element)
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
            bindHandlers(element, bound, binding, compiled.Text)
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
