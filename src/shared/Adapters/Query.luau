--!strict
--[[
    Unrest / Adapters / Query

    The selector engine behind `Unrest:Query`.

    A query is *live*, not a one-shot scan -- that is what the whiteboard's arrow into
    CollectionService means. Two sets are maintained:

      * watched  -- every candidate the source can produce (everything carrying the tag, or
                    everything in the ancestor subtree). Each watched instance keeps a small
                    scope holding a `Destroying` connection plus exactly the property and
                    attribute connections this descriptor actually needs: a `Name` or `Role`
                    filter earns a `Name` watch, a `Role` or `Group` filter earns an
                    attribute watch, and a class-only filter earns neither.
      * bindings -- the subset that currently matches. Each keeps a scope holding the event
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

    The bookkeeping that keeps a cascading source live -- the tagged roots, their
    `DescendantAdded`, the `UnrestIgnore` watch per gate, the re-sweeps -- is not written
    here either. It is `Cascade`, one ledger shared with `Elements`, and this module supplies
    only what it does with the answer: cover means `watch`, uncover means `unwatch`. When
    either happens is `Cascade`'s question, and it used to be answered twice.

    Liveness costs, for a cascading descriptor: whatever the ledger spends (one
    `DescendantAdded` per tagged root, one `UnrestIgnore` watch per gate) plus, per watched
    candidate, an `AncestryChanged` and an `UnrestIgnore` watch on top of the `Destroying` it
    already had. Coverage is a fact about the chain above an element, and those two are the
    only edits that can change it.

    ---------------------------------------------------------------------------
    Nothing is counted that is not bound
    ---------------------------------------------------------------------------

    An element is either bound and counted, or absent. There is no third state, and there are
    two places that have to hold that line.

    `attach` binds *before* it records. An element whose class cannot honour one of the bound
    handlers never enters `elements` or `bindings`, so `:Count()` can never report something
    that is wired to nothing, and `Added` / `ElementAdded` fire only for elements that really
    arrived. Recording first, as this used to, left a refused element counted, handed out by
    `:Elements()`, holding a scope with nothing in it, and announced by no signal at all.

    `Bind` is atomic. The merge is proposed against a copy, every element the query currently
    holds is asked whether it can take that copy, and only "all of them" is allowed to change
    anything. A refusal raises before `bound` or a single binding has been touched. Merging
    first and rebuilding afterwards -- which is what it used to do -- failed three ways at
    once on a heterogeneous set: the elements the loop had already reached were rebuilt around
    the new handler, the one that raised and every element after it were left with a scope that
    had been cleaned and never refilled, and the handler that could not bind stayed in `bound`
    so every later arrival raised on it too.

    ---------------------------------------------------------------------------
    Elements that arrive later
    ---------------------------------------------------------------------------

    `Bind` can only answer for the elements the query holds at the moment it is called. A
    `Frame` tagged five minutes afterwards can match a descriptor whose bound handlers only a
    button can honour, and no amount of checking at `Bind` time can know that in advance.

    Such an element is refused exactly as it would have been at `Bind` time and stays out of
    the set -- not counted, not in `elements`, no `Added`. It keeps its watch, so a later
    rename or attribute edit asks the question again; and because `Bind` only ever *adds*
    handler names, a refusal can never turn into an acceptance by binding more.

    The refusal stays an error rather than becoming a warning. This is code binding a handler
    its element cannot support, which is the raising half of "code raises, attributes warn",
    and quietly dropping the element would hide exactly the kind of half-wired screen the two
    fixes above exist to prevent. What differs is *where* it lands:

      * during `Query.new`'s first sourcing pass the caller who wrote the handler table is on
        the stack, so it raises there and the `Unrest:Query` call throws;
      * afterwards there is no such caller. The element arrived through a CollectionService
        signal or a cascade sweep, and unwinding through one of those would abandon the rest
        of the walk -- a panel parented in whole would leave every sibling the sweep had not
        reached yet unwatched, which is the same half-built set by another route. So the
        refusal is raised on its own thread: it still reaches the output window with a
        traceback, and the walk that found the element finishes.
]]

local CollectionService = game:GetService("CollectionService")

local Adapters = require(script.Parent)
local Cascade = require(script.Parent.Cascade)
local Constants = require(script.Parent.Parent.Constants)
local Resolver = require(script.Parent.Parent.Util.Resolver)
local Scope = require(script.Parent.Parent.Util.Scope)
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
    --[[
        Asked of the list rather than of `Selector.watchesAncestors`, which answers by building
        the very list already in hand. Calling it here ran `triggers` a third time for one
        boolean.
    ]]
    local watchesAncestors = #ancestorAttributes > 0
    local hint = `Narrow the query {compiled.Text} with a Selector or a Role, or drop that handler.`

    local tag = compiled.Tag
    --- Whether this descriptor's tag is the framework's own, and therefore cascades.
    local cascading = tag ~= nil and Selector.cascades(tag)

    local lifetime = Scope.scope()
    local watched: { [Instance]: Types.Scope } = {}
    local bindings: { [Instance]: Types.Scope } = {}
    local elements: { Instance } = {}
    --[[
        The cascade ledger, built once `watch` and `unwatch` exist because they are what it
        covers and uncovers with. `nil` for a non-cascading source: an exact tag and an
        ancestor subtree both enumerate themselves and have no roots or gates to keep.
    ]]
    local cascade: Cascade.CascadeEngine? = nil
    local destroyed = false
    --[[
        True only while the sourcing block below is still assembling the first set, which is
        the one window in which the code that supplied `handlers` is on the stack. That is the
        whole of the difference between the two ways `attach` reports a refusal -- see
        "Elements that arrive later" in the header.
    ]]
    local sourcing = true

    local elementAdded: Types.Signal<Instance> = Signal.new("Query.ElementAdded")
    local elementRemoved: Types.Signal<Instance> = Signal.new("Query.ElementRemoved")
    Scope.addBulk(lifetime, elementAdded, elementRemoved)

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
        Scope.destroy(binding)

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

    --[[
        Bind first, record second. Everything before the `Adapters.bind` call is local to this
        function, so an element the registry refuses leaves the set exactly as it found it:
        nothing in `bindings`, nothing in `elements`, no `Added`, no `ElementAdded`.

        The refusal is asked for up front rather than caught afterwards, because who gets to
        hear about it depends on how this element got here, and only the header's two cases
        can tell those apart. `Adapters.bind` would raise the identical sentence a moment
        later; asking first is what lets this choose the thread it raises on.
    ]]
    local function attach(element: Instance): ()
        if bindings[element] ~= nil then
            return
        end

        local rejection = Adapters.rejects(registry, element, bound, hint)
        if rejection ~= nil then
            if sourcing then
                error(rejection, 0)
            end
            task.spawn(function()
                error(rejection, 0)
            end)
            return
        end

        local binding = Scope.scope()
        -- The rejection above is the pre-flight, so binding must not run it a second time.
        Adapters.bindChecked(registry, element, bound, binding, hint)

        bindings[element] = binding
        table.insert(elements, element)

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
            Scope.destroy(watcher)
        end
        detach(element)
    end

    --[[
        A `Group` filter reads through the element to the chain above it, so an edit up there
        moves the element in or out of this set just as surely as an edit on the element
        itself. The whole chain is watched, not only the ancestor supplying a value today: a
        nearer one that sets `UnrestGroup` tomorrow takes precedence the moment it does.

        `Selector.ancestorTriggers` says which attributes those are, so this watches every
        inheritable input to the answer rather than only the one the filter names -- an
        `UnrestPreset` on a ScreenGui can supply the group, and swapping it has to move the
        elements underneath the same way editing `UnrestGroup` there does.

        `chain` is a scope of its own, cleaned and refilled rather than replaced, so
        reparenting drops the previous chain outright instead of accumulating connections to
        ancestors the element no longer has. It is linked under the element's watcher, so it
        goes when the watcher does.
    ]]
    local function bindAncestry(element: Instance, chain: Types.Scope, onChanged: () -> ()): ()
        Scope.clean(chain)

        for _, ancestor in Selector.ancestorChain(element) do
            for _, attribute in ancestorAttributes do
                Scope.add(chain, ancestor:GetAttributeChangedSignal(attribute):Connect(onChanged))
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
            local watcher = Scope.scope()
            watched[element] = watcher

            --[[
                One closure, reused by every connection below. Built per candidate rather than
                per signal: the three loops here would otherwise mint a closure apiece, and
                `bindAncestry` one per ancestor per attribute, all of them the same two lines.
            ]]
            local function onChanged(): ()
                evaluate(element)
            end

            local chain: Types.Scope? = nil
            if watchesAncestors then
                chain = Scope.add(watcher, Scope.scope())
            end

            -- A rename, or an edit to UnrestRole / UnrestGroup, can move an element in or out.
            for _, property in watchedProperties do
                Scope.add(watcher, element:GetPropertyChangedSignal(property):Connect(onChanged))
            end
            for _, attribute in watchedAttributes do
                Scope.add(watcher, element:GetAttributeChangedSignal(attribute):Connect(onChanged))
            end
            if chain ~= nil then
                bindAncestry(element, chain, onChanged)
            end

            --[[
                Moving anywhere above the element changes which ancestors it reads from, and
                is exactly the set of moves that can change the answer -- for an inherited
                `UnrestGroup`, and for whether a cascading tag still reaches the element at
                all. One connection answers both.
            ]]
            if cascading or watchesAncestors then
                Scope.add(
                    watcher,
                    element.AncestryChanged:Connect(function()
                        if chain ~= nil then
                            bindAncestry(element, chain, onChanged)
                        end
                        local ledger = cascade
                        if ledger ~= nil then
                            ledger:Reconcile(element)
                        else
                            evaluate(element)
                        end
                    end)
                )
            end
            if cascading then
                -- Excluding this element excludes everything under it, so the whole subtree
                -- is re-asked rather than just this one.
                Scope.add(
                    watcher,
                    element:GetAttributeChangedSignal(Constants.Attributes.Ignore):Connect(function()
                        local ledger = cascade
                        if ledger ~= nil then
                            ledger:IgnoreChanged(element)
                        end
                    end)
                )
            end

            Scope.add(
                watcher,
                element.Destroying:Connect(function()
                    unwatch(element)
                end)
            )
        end

        evaluate(element)
    end

    --------------------------------------------------------------------------------
    -- Sourcing: tags win, otherwise the ancestor subtree.
    --------------------------------------------------------------------------------

    if tag ~= nil then
        if cascading then
            --[[
                A tagged instance is a root, not a result: it brings itself and everything the
                cascade reaches under it, and untagging one re-asks the question for what is
                under it rather than dropping the lot. The ledger owns all of that; watching
                and unwatching a candidate is this module's half of the deal.
            ]]
            local engine = Cascade.new({
                Cover = watch,
                Uncover = unwatch,
                Tracks = function(instance: Instance): boolean
                    return watched[instance] ~= nil
                end,
                Covered = function(): { Instance }
                    local covered: { Instance } = {}
                    for instance in watched do
                        table.insert(covered, instance)
                    end
                    return covered
                end,
            })
            cascade = engine
            engine:Source(tag)
        else
            Scope.addBulk(
                lifetime,
                CollectionService:GetInstanceAddedSignal(tag):Connect(watch),
                CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch)
            )
            for _, element in CollectionService:GetTagged(tag) do
                watch(element)
            end
        end
    else
        local ancestor = compiled.Ancestor :: Instance
        if compiled.Recursive then
            Scope.addBulk(
                lifetime,
                ancestor.DescendantAdded:Connect(watch),
                ancestor.DescendantRemoving:Connect(unwatch)
            )
            for _, element in ancestor:GetDescendants() do
                watch(element)
            end
        else
            Scope.addBulk(lifetime, ancestor.ChildAdded:Connect(watch), ancestor.ChildRemoved:Connect(unwatch))
            for _, element in ancestor:GetChildren() do
                watch(element)
            end
        end
    end

    -- Past here every arrival is the element's own news rather than this call's.
    sourcing = false

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
        --[[
            Walked backwards over the live array rather than over a clone. A visitor that
            removes the element it is handed -- the reason the clone was here -- only ever
            shortens the array behind the cursor, so an index counting down never skips and
            never re-visits. One table per `:Each` call saved, and a game may call it in a loop.
        ]]
        for index = #elements, 1, -1 do
            visitor(elements[index], nil)
        end
        return typed
    end

    function handle:Bind(extra: Types.Handlers): Types.QueryHandle
        if destroyed then
            error(`[Unrest.Query] :Bind called on a destroyed query {compiled.Text}.`, 0)
        end

        local validated = Resolver.Handlers(extra)

        --[[
            Proposed, checked, and only then committed. The merge lands in a copy, so a
            refusal from any single element can raise with `bound` untouched -- and it has to,
            because the alternative leaves a handler nothing can bind sitting in the table
            every future arrival is bound against.
        ]]
        local merged: { [string]: any } = table.clone(bound :: { [string]: any })
        for key, value in validated :: { [string]: any } do
            merged[key] = value
        end
        local proposed = (merged :: any) :: Types.Handlers

        for element in bindings do
            local rejection = Adapters.rejects(registry, element, proposed, hint)
            if rejection ~= nil then
                error(rejection, 0)
            end
        end

        bound = proposed

        --[[
            Every element has already said yes, so nothing below can raise and leave a scope
            cleaned but unfilled. Rebuilt rather than added to, so a replaced handler does not
            leave its predecessor connected alongside it.
        ]]
        for element, binding in bindings do
            Scope.clean(binding)
            Adapters.bindChecked(registry, element, bound, binding, hint)
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

        local ledger = cascade
        if ledger ~= nil then
            ledger:Destroy()
        end

        Scope.destroy(lifetime)
    end

    return typed
end

return Query
