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

    ---------------------------------------------------------------------------
    Sourcing the framework tag
    ---------------------------------------------------------------------------

    `CollectionService:GetTagged` returns the instances somebody tagged, and the framework tag
    manages more than those: it cascades to every `GuiObject` underneath. So a descriptor
    naming that tag sources through `Selector.cascadeUnder` and filters through
    `Selector.isManaged` -- the same predicate `Elements` adopts with. Sourcing candidates from
    the raw tag list instead would leave a cascaded button adopted, wired, and invisible to the
    query that asked for it, which is worse than never adopting it.

    Any other tag is still exact. `Tag = "Highlighted"` means the instances carrying that tag,
    because a foreign tag is a label rather than an opt-in.

    Liveness costs, for a cascading descriptor: one `DescendantAdded` per tagged root, one
    `UnrestIgnore` watch per gate (`Selector.isGate` -- an ignored instance, or a Folder the
    cascade passes through), and, per watched candidate, an `AncestryChanged` and an
    `UnrestIgnore` watch on top of the `Destroying` it already had. Coverage is a fact about
    the chain above an element, and those two are the only edits that can change it.
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
    local ancestorAttributes = Selector.ancestorTriggers(compiled)
    local watchesAncestors = Selector.watchesAncestors(compiled)
    local hint = `Narrow the query {compiled.Text} with a Selector or a Role, or drop that handler.`

    local tag = compiled.Tag
    --- Whether this descriptor's tag is the framework's own, and therefore cascades.
    local cascading = tag ~= nil and Selector.cascades(tag)

    local lifetime = Maid.new()
    local watched: { [Instance]: Types.Maid } = {}
    local bindings: { [Instance]: Types.Maid } = {}
    local elements: { Instance } = {}
    --- One `DescendantAdded` per tagged root, so cascaded arrivals are seen.
    local roots: { [Instance]: Types.Maid } = {}
    --- `UnrestIgnore` watches on instances that shape the managed set without being in it.
    local gates: { [Instance]: Types.Maid } = {}
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

    --- Defined below, once `watch` exists: coverage and `UnrestIgnore` both feed back into it.
    local reconcileWatch: (instance: Instance) -> ()
    local onIgnoreChanged: (instance: Instance) -> ()

    --[[
        A `Group` filter reads through the element to the chain above it, so an edit up there
        moves the element in or out of this set just as surely as an edit on the element
        itself. The whole chain is watched, not only the ancestor supplying a value today: a
        nearer one that sets `UnrestGroup` tomorrow takes precedence the moment it does.

        `Selector.ancestorTriggers` says which attributes those are, so this watches every
        inheritable input to the answer rather than only the one the filter names -- an
        `UnrestPreset` on a ScreenGui can supply the group, and swapping it has to move the
        elements underneath the same way editing `UnrestGroup` there does.

        Rebuilt under a keyed maid slot, so reparenting drops the previous chain outright
        rather than accumulating connections to ancestors the element no longer has.
    ]]
    local function bindAncestry(element: Instance, watcher: Types.Maid): ()
        local chain = Maid.new()
        watcher:Add(chain, "ancestry")

        for _, ancestor in Selector.ancestorChain(element) do
            for _, attribute in ancestorAttributes do
                chain:Add(ancestor:GetAttributeChangedSignal(attribute):Connect(function()
                    evaluate(element)
                end))
            end
        end
    end

    --[[
        Idempotent, and always ends by re-asking whether the candidate matches -- so the same
        call both starts watching a new candidate and re-tests one that is already watched.
    ]]
    local function watch(element: Instance): ()
        if destroyed then
            return
        end

        if watched[element] == nil then
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
            end

            --[[
                Moving anywhere above the element changes which ancestors it reads from, and
                is exactly the set of moves that can change the answer -- for an inherited
                `UnrestGroup`, and for whether a cascading tag still reaches the element at
                all. One connection answers both.
            ]]
            if cascading or watchesAncestors then
                watcher:Add(element.AncestryChanged:Connect(function()
                    if watchesAncestors then
                        bindAncestry(element, watcher)
                    end
                    if cascading then
                        reconcileWatch(element)
                    else
                        evaluate(element)
                    end
                end))
            end
            if cascading then
                -- Excluding this element excludes everything under it, so the whole subtree
                -- is re-asked rather than just this one.
                watcher:Add(element:GetAttributeChangedSignal(Constants.Attributes.Ignore):Connect(function()
                    onIgnoreChanged(element)
                end))
            end

            watcher:Add(element.Destroying:Connect(function()
                unwatch(element)
            end))
        end

        evaluate(element)
    end

    --------------------------------------------------------------------------------
    -- Cascade sourcing
    --------------------------------------------------------------------------------

    --[[
        Coverage, re-derived rather than counted: an element under two tagged ancestors is
        asked the question again and keeps answering yes until both are gone.
    ]]
    function reconcileWatch(instance: Instance): ()
        if destroyed then
            return
        end
        if Selector.isManaged(instance) then
            watch(instance)
        else
            unwatch(instance)
        end
    end

    --[[
        Watches `UnrestIgnore` on an instance this query does not track but whose attribute
        decides what it tracks underneath. Kept once discovered -- the set is bounded by the
        shape of the tree, and a stale gate only ever re-asks a settled question.
    ]]
    local function watchGate(instance: Instance): ()
        if destroyed or gates[instance] ~= nil then
            return
        end

        local maid = Maid.new()
        gates[instance] = maid
        maid:Add(instance:GetAttributeChangedSignal(Constants.Attributes.Ignore):Connect(function()
            onIgnoreChanged(instance)
        end))
        maid:Add(instance.Destroying:Connect(function()
            local watcher = gates[instance]
            gates[instance] = nil
            if watcher ~= nil then
                watcher:Destroy()
            end
        end))
    end

    local function dropGate(instance: Instance): ()
        local maid = gates[instance]
        if maid == nil then
            return
        end
        gates[instance] = nil
        maid:Destroy()
    end

    --- Everything the cascade reaches under `root`, plus the gates that keep it live.
    local function sweepInto(root: Instance): ()
        local cascaded, gated = Selector.cascadeUnder(root)
        for _, instance in cascaded do
            reconcileWatch(instance)
        end
        for _, instance in gated do
            watchGate(instance)
        end
    end

    --[[
        `UnrestIgnore` went on or came off. Both directions are the same three steps: keep
        listening, re-ask for what is already watched under it, then enumerate what the edit
        may have brought back. One of the last two is always a no-op.
    ]]
    function onIgnoreChanged(instance: Instance): ()
        if destroyed then
            return
        end

        watchGate(instance)
        reconcileWatch(instance)
        for other in table.clone(watched) do
            if other:IsDescendantOf(instance) then
                reconcileWatch(other)
            end
        end
        sweepInto(instance)

        if watched[instance] ~= nil then
            dropGate(instance)
        end
    end

    --[[
        One `DescendantAdded` per tagged root and nothing per descendant. Departures are not
        watched here: every candidate carries its own `AncestryChanged`, which fires after the
        move with the final parent in place.
    ]]
    local function addRoot(root: Instance): ()
        if destroyed or roots[root] ~= nil then
            return
        end

        local maid = Maid.new()
        roots[root] = maid
        maid:Add(root.DescendantAdded:Connect(function(instance: Instance)
            if destroyed then
                return
            end
            for _, gate in Selector.gatesAbove(instance, root) do
                watchGate(gate)
            end
            reconcileWatch(instance)
        end))
    end

    local function onTagged(root: Instance): ()
        addRoot(root)
        reconcileWatch(root)
        sweepInto(root)
    end

    local function onUntagged(root: Instance): ()
        local maid = roots[root]
        if maid ~= nil then
            roots[root] = nil
            maid:Destroy()
        end

        -- Coverage can only shrink, and only under the root that lost the tag.
        reconcileWatch(root)
        for instance in table.clone(watched) do
            if instance:IsDescendantOf(root) then
                reconcileWatch(instance)
            end
        end
    end

    -- Sourcing: tags win, otherwise the ancestor subtree.
    if tag ~= nil then
        if cascading then
            --[[
                A tagged instance is a root, not a result: it brings itself and everything the
                cascade reaches under it. Untagging one re-asks the question for what is under
                it, which keeps whatever a second tagged ancestor still covers.
            ]]
            lifetime:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(onTagged))
            lifetime:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(onUntagged))
            for _, root in CollectionService:GetTagged(tag) do
                onTagged(root)
            end
        else
            lifetime:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(watch))
            lifetime:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch))
            for _, element in CollectionService:GetTagged(tag) do
                watch(element)
            end
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

        for _, maid in roots do
            maid:Destroy()
        end
        table.clear(roots)
        for _, maid in gates do
            maid:Destroy()
        end
        table.clear(gates)

        lifetime:Destroy()
    end

    return typed
end

return Query
