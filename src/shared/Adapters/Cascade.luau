--!strict
--[[
    Unrest / Adapters / Cascade

    The bookkeeping behind the cascading tag, written once.

    `Selector` says *what* the cascade means -- `isManaged` is the predicate, `cascadeUnder`
    the enumeration, `isGate` and `gatesAbove` the gates. None of that lives here and none of
    it is repeated here. What lives here is the other half: the ledger that keeps those
    answers *live*. Which tagged roots exist, one `DescendantAdded` on each, an `UnrestIgnore`
    watch on every gate, and the re-sweeps that follow a tag or an ignore being edited while
    the game runs.

    `Elements` and `Query` both need that ledger and used to carry a copy each. They had
    drifted before and the repo has been bitten four separate times by one question answered
    in two places, so the ledger is one object now and the two callers differ only in what
    they *do* with the answer:

        Elements  covers by adopting and wiring;   uncovers by releasing.
        Query     covers by watching a candidate;  uncovers by dropping the watch.

    *When* either happens is identical, and that is the whole of what this module owns.

    ---------------------------------------------------------------------------
    Coverage is re-derived, never counted
    ---------------------------------------------------------------------------

    Every path that can change coverage ends at `reconcile`, which asks `Selector.isManaged`
    again. An element under two tagged ancestors is not held by two references: it is asked
    the question a second time and keeps answering yes until both are gone. Nothing has to be
    decremented in the right order and no counter can drift out of step with the tree it
    describes.

    ---------------------------------------------------------------------------
    The connection budget, in full
    ---------------------------------------------------------------------------

      * one `DescendantAdded` per tagged root -- nothing per descendant;
      * one `UnrestIgnore` watch plus one `Destroying` per gate (`Selector.isGate`: an
        ignored instance, or a non-`GuiObject` the cascade descends through);
      * nothing else. What a covered instance watches on its own behalf belongs to the host,
        not to this ledger.

    There is deliberately no `DescendantRemoving`. Leaving is the element's own news: a host
    watches `AncestryChanged` on what it covers, and that fires *after* the move with the
    final parent in place, so the question it re-asks has a true answer.
    `DescendantRemoving` fires while the element is still where it was and could only ask the
    question one step too early.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Parent.Constants)
local Scope = require(script.Parent.Parent.Util.Scope)
local Selector = require(script.Parent.Selector)
local Types = require(script.Parent.Parent.Types)

local IGNORE = Constants.Attributes.Ignore

--[[
    What the host does with the ledger's answers.

    `Cover` and `Uncover` are the two halves of one decision -- `Selector.isManaged` said yes,
    or it said no -- and are allowed to be no-ops: `Elements` refuses to release an instance
    somebody `:Adopt`ed by hand, and neither call needs to know whether it changed anything.

    `Tracks` and `Covered` are how the ledger reads the host's set back. `Tracks` answers for
    one instance ("did you take it?"), `Covered` hands over a snapshot to walk. The snapshot
    is the host's own, in the host's own order, because a release order is the host's business
    and not this module's.
]]
export type CascadeHost = {
    Cover: (instance: Instance) -> (),
    Uncover: (instance: Instance) -> (),
    Tracks: (instance: Instance) -> boolean,
    Covered: () -> { Instance },
}

--[[
    The ledger. `Source` starts it on a tag; `Reconcile` and `IgnoreChanged` are the two
    events a host can see before this module does -- an element it covers moving, and an
    element it covers having its own `UnrestIgnore` edited.
]]
export type CascadeEngine = {
    Reconcile: (self: CascadeEngine, instance: Instance) -> (),
    IgnoreChanged: (self: CascadeEngine, instance: Instance) -> (),
    Source: (self: CascadeEngine, tag: string) -> (),
    Destroy: (self: CascadeEngine) -> (),
}

local Cascade = {}

--- Creates a ledger. Nothing is connected until `:Source(tag)`.
function Cascade.new(host: CascadeHost): CascadeEngine
    local lifetime = Scope.scope()
    --- One `DescendantAdded` per tagged root, so cascaded arrivals are seen.
    local roots: { [Instance]: Types.Scope } = {}
    --- `UnrestIgnore` watches on instances that shape the covered set without being in it.
    local gates: { [Instance]: Types.Scope } = {}
    local destroyed = false

    local engine = {}
    local typed = (engine :: any) :: CascadeEngine

    --- Defined below; the gate watches and the ignore sweep are mutually recursive.
    local onIgnoreChanged: (instance: Instance) -> ()

    --- Asks `Selector` again and hands the answer to the host. Every path ends here.
    local function reconcile(instance: Instance): ()
        if destroyed then
            return
        end

        if Selector.isManaged(instance) then
            host.Cover(instance)
        else
            host.Uncover(instance)
        end
    end

    --[[
        Watches `UnrestIgnore` on an instance the host does not cover but whose attribute
        still decides what it covers underneath -- a Folder the cascade passes through, or the
        ignored Frame it stopped at. `Selector.isGate` names them.

        Once discovered a gate is kept, even after the tag above it goes away. The set is
        bounded by the shape of the tree rather than by how often tags are edited, and a gate
        whose subtree is no longer covered only ever re-asks a question that answers "nothing
        to do".
    ]]
    local function watchGate(instance: Instance): ()
        if destroyed or gates[instance] ~= nil then
            return
        end

        local scope = Scope.scope()
        gates[instance] = scope
        Scope.addBulk(
            scope,
            instance:GetAttributeChangedSignal(IGNORE):Connect(function()
                onIgnoreChanged(instance)
            end),
            instance.Destroying:Connect(function()
                local watcher = gates[instance]
                gates[instance] = nil
                if watcher ~= nil then
                    Scope.destroy(watcher)
                end
            end)
        )
    end

    local function dropGate(instance: Instance): ()
        local scope = gates[instance]
        if scope == nil then
            return
        end
        gates[instance] = nil
        Scope.destroy(scope)
    end

    --- Everything the cascade reaches under `root`, plus the gates that keep it live.
    local function sweep(root: Instance): ()
        local cascaded, gated = Selector.cascadeUnder(root)

        --[[
            Covered directly rather than reconciled. `reconcile` exists to ask `isManaged`,
            which walks from the instance up to the tagged root testing the tag and
            `UnrestIgnore` at every step -- and `Selector.cascadeUnder` guarantees, in its own
            header, that everything in this list already satisfies exactly that predicate. The
            walk it prunes with and the walk `isManaged` performs are the same walk.

            Re-asking made a sweep of an N-node screen of depth D do N x D redundant
            `HasTag` / `GetAttribute` crossings, once at startup for every tagged root and
            again on every tag or `UnrestIgnore` edit. The `destroyed` check `reconcile` opens
            with is kept, because a host that shut down mid-sweep must not be handed more.
        ]]
        for _, instance in cascaded do
            if destroyed then
                return
            end
            host.Cover(instance)
        end

        for _, instance in gated do
            watchGate(instance)
        end
    end

    --[[
        Re-asks the question for `root` and for everything the host already covers under it.
        The host's set is walked rather than the tree, so untagging a ScreenGui costs the
        elements it covered and not the instances it contains.
    ]]
    local function reconcileUnder(root: Instance): ()
        reconcile(root)
        for _, instance in host.Covered() do
            if instance ~= root and instance:IsDescendantOf(root) then
                reconcile(instance)
            end
        end
    end

    --[[
        `UnrestIgnore` went on or came off. Both directions are the same steps -- keep
        listening, re-ask for what is already covered under it, then enumerate what the edit
        may have brought back -- because one of the last two is always a no-op and neither
        needs to know which way the edit went.
    ]]
    function onIgnoreChanged(instance: Instance): ()
        if destroyed then
            return
        end

        -- Something must stay attached across the release, or the edit that clears the
        -- attribute again would have nobody left listening for it.
        watchGate(instance)

        reconcileUnder(instance)
        sweep(instance)

        if host.Tracks(instance) then
            -- Covered again: whatever the host attaches to what it covers carries the watch
            -- from here.
            dropGate(instance)
        end
    end

    --[[
        One `DescendantAdded` per tagged root, and nothing per descendant. A GuiObject
        parented into a covered subtree is reconciled on arrival -- and so is every GuiObject
        of a whole panel parented in at once, because the signal fires once for each of them.

        An arrival can also *create* a gate: a Folder that was empty when the screen was swept
        is a Folder the cascade now descends through, so the containers above the newcomer are
        re-tested rather than assumed unchanged.
    ]]
    local function addRoot(root: Instance): ()
        if destroyed or roots[root] ~= nil then
            return
        end

        local scope = Scope.scope()
        roots[root] = scope
        Scope.add(
            scope,
            root.DescendantAdded:Connect(function(instance: Instance)
                if destroyed then
                    return
                end
                for _, gate in Selector.gatesAbove(instance, root) do
                    watchGate(gate)
                end
                reconcile(instance)
            end)
        )
    end

    --[[
        A tagged instance is a root, not merely a result: it brings itself and everything the
        cascade reaches under it.

        The root can be one the host declines -- `Elements` will not adopt a tagged Folder,
        because no adapter matches its class. Its `UnrestIgnore` still decides what the
        cascade does underneath and nothing else would be watching it, so it becomes a gate.
    ]]
    local function onTagAdded(root: Instance): ()
        addRoot(root)
        reconcile(root)
        if not host.Tracks(root) then
            watchGate(root)
        end
        sweep(root)
    end

    --[[
        The root stops being a root. Coverage can only shrink, and only under it: whatever a
        second tagged ancestor still covers keeps answering yes to the same question.
    ]]
    local function onTagRemoved(root: Instance): ()
        local scope = roots[root]
        if scope ~= nil then
            roots[root] = nil
            Scope.destroy(scope)
        end

        reconcileUnder(root)
    end

    function engine:Reconcile(instance: Instance): ()
        reconcile(instance)
    end

    function engine:IgnoreChanged(instance: Instance): ()
        onIgnoreChanged(instance)
    end

    --[[
        Starts the ledger on `tag`: the two CollectionService signals, then one pass over
        what is already tagged. Safe to call once per engine.
    ]]
    function engine:Source(tag: string): ()
        if destroyed then
            return
        end

        Scope.addBulk(
            lifetime,
            CollectionService:GetInstanceAddedSignal(tag):Connect(onTagAdded),
            CollectionService:GetInstanceRemovedSignal(tag):Connect(onTagRemoved)
        )

        for _, root in CollectionService:GetTagged(tag) do
            onTagAdded(root)
        end
    end

    --[[
        Drops the ledger. The host's own set is the host's to tear down -- this releases the
        root and gate connections only, and stops answering.
    ]]
    function engine:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        for _, scope in roots do
            Scope.destroy(scope)
        end
        table.clear(roots)
        for _, scope in gates do
            Scope.destroy(scope)
        end
        table.clear(gates)

        Scope.destroy(lifetime)
    end

    return typed
end

return Cascade
