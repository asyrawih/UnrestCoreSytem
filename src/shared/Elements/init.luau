--!strict
--[[
    Unrest / Elements

    Adoption. The half of the framework that turns Studio-built UI into framework UI without
    the framework ever having created a single GuiObject.

    The whole opt-in is one CollectionService tag. Tagging an instance `Unrest` means:

      * an adapter is resolved for its ClassName, so the framework knows what it can do;
      * its `Unrest*` attributes are resolved and wired, live -- editing one in Studio while
        the game runs re-wires that element and nothing else;
      * it becomes visible to `Unrest:Query`.

    Untagging (or destroying, or `:Release`ing) undoes all of that. Every connection an
    element owns hangs off one maid, so release is one line and cannot half-happen.

    ---------------------------------------------------------------------------
    The tag cascades
    ---------------------------------------------------------------------------

    Tagging an instance manages that instance *and* every `GuiObject` under it, so a screen
    is opted in by tagging its container once rather than by tagging forty buttons. Tag a
    single button and you still get a single button, because a button rarely has GuiObject
    children -- one rule, and it reads correctly both ways.

    Only `GuiObject` descendants are swept up. A `UIListLayout`, `UIPadding` or `UIStroke`
    under a tagged Frame is left alone: it carries no events and exists to lay other things
    out, so adopting it would be noise. Tagging one yourself still adopts it, which is how a
    channel gets bound to a `UIStroke.Color`.

    `UnrestIgnore = true` opts an instance and its whole subtree back out, live in both
    directions, for the one decorative subtree inside an otherwise managed screen.

    The rule itself is not written here. `Selector.isManaged` is the predicate,
    `Selector.cascadeUnder` the enumeration, and `Query` sources from the same two -- because
    an element this manager adopted and wired but a query could not find would be worse than
    an element nobody adopted at all.

    Coverage is re-derived, never counted. Anything that can change it ends at `reconcile`,
    which asks `Selector` again; an element covered by two tagged ancestors keeps answering
    yes until both are gone, with no reference count to keep in step with the tree.

    The connection budget, in full: one `DescendantAdded` per tagged root, one
    `UnrestIgnore` watch per gate (`Selector.isGate`), and -- on adopted elements only, which
    already carry a maid -- one more `UnrestIgnore` watch each. Nothing is connected to an
    instance the framework does not manage and could not adopt.

    ---------------------------------------------------------------------------
    Zero-code wiring
    ---------------------------------------------------------------------------

    A designer with no Luau at all can build a working button:

        Tag           Unrest
        UnrestCommand "Example.Action"
        UnrestPayload "Confirm"

    and a label that follows framework state:

        Tag           Unrest
        UnrestChannel "Example.Status"
        UnrestBind    "Text"
        UnrestFormat  "Status: {value}"

    An attribute grants no privilege. `UnrestCommand` goes through the same
    `Bridge:Dispatch` as hand-written Luau, so the command's contract still decides whether
    the request is allowed to happen at all. Adding an attribute in Studio can never widen
    what a client may ask for -- the permission was never in the attribute.

    ---------------------------------------------------------------------------
    Resolution: three layers, most specific wins
    ---------------------------------------------------------------------------

    `element.Attributes` is not a copy of the instance's attributes any more. Every key is
    resolved through three layers, most specific winning:

        1. the element -- whatever the designer set on this instance (strongest);
        2. the preset  -- the bundle named by `UnrestPreset`, from `Presets.luau`;
        3. inheritance -- the nearest ancestor that sets one of `Constants.Inheritable`.

    So a preset is a default and never an override, and an ancestor is a fallback and never
    a mandate. `element.Sources` records which layer won each key, so "who set this?" has an
    answer without reading three places in Studio.

    That precedence is **not written here**. It is `Selector.attributeOf`, and `Selector` asks
    the same function when it decides what `Query({ Group = ... })` matches. It used to be
    written in both places, and the two drifted: a preset inherited from a ScreenGui expanded
    here into an `element.Group` no query could find. One function, one answer.

    Only the three names in `Constants.Inheritable` are ever inherited, because the rule is
    *inherit context, never intent*. `UnrestGroup` says which screen an element is on and
    every element on that screen shares the answer; `UnrestCommand` says what this one
    button does, and inheriting it would silently arm every descendant of a panel with the
    same command. Role, command, payload, channel, bind and format are therefore per-element
    and stay that way.

    The walk is `Selector.ancestorChain`. It stops at the first `LayerCollector` -- a screen is
    the widest thing an inheritable attribute is allowed to mean -- and never reads a service
    or the DataModel, because `UnrestGroup` on `Players` would be a global.

    ---------------------------------------------------------------------------
    Loud vs. fatal
    ---------------------------------------------------------------------------

    Code that binds a handler its element cannot support is a bug, and `Unrest:Query` throws.
    An attribute that asks for the same thing is *data*, usually typed by somebody who is
    not looking at the output window, and taking the rest of the screen down with it would
    be a worse outcome than a warning naming the element, its class and what that class
    actually supports. So attribute wiring warns and skips; code binding raises.

    An `UnrestPreset` nobody declared is the same kind of mistake, and gets the same
    treatment: a warning naming the value and listing the presets that do exist, and then
    the element is adopted with its own attributes only.
]]

local CollectionService = game:GetService("CollectionService")

local Adapters = require(script.Parent.Adapters)
local Constants = require(script.Parent.Constants)
local Maid = require(script.Parent.Util.Maid)
local Presets = require(script.Parent.Presets)
local Query = require(script.Parent.Adapters.Query)
local Selector = require(script.Parent.Adapters.Selector)
local Signal = require(script.Parent.Util.Signal)
local Types = require(script.Parent.Types)

local Elements = {}

local ATTRIBUTES = Constants.Attributes

--- Every attribute the manager reads off the element itself, so one loop wires all the
--- change signals and one loop reads the strongest layer of the merge.
local WATCHED: { string } = {
    ATTRIBUTES.Role,
    ATTRIBUTES.Group,
    ATTRIBUTES.Command,
    ATTRIBUTES.Payload,
    ATTRIBUTES.Channel,
    ATTRIBUTES.Bind,
    ATTRIBUTES.Format,
    ATTRIBUTES.Cooldown,
    ATTRIBUTES.Preset,
}

--[[
    `Constants.Inheritable` as a stable list. Sorted, so the ancestor walk, the watches it
    installs and anything printed from it are in a fixed order rather than a hash order.
]]
local INHERITABLE: { string } = {}
for name in (Constants.Inheritable :: any) :: { [string]: boolean } do
    table.insert(INHERITABLE, name)
end
table.sort(INHERITABLE)

--[[
    `UnrestFormat` is a template with one hole, not a format string: designers write
    "Status: {value}", never "%s". A function replacement is used so a `%` in the value is a
    literal per cent sign rather than a gsub escape.
]]
local function applyFormat(format: string, value: any): string
    local text = if value == nil then "" else tostring(value)
    local rendered = string.gsub(format, "{value}", function()
        return text
    end)
    return rendered
end

local function readString(source: { [string]: any }, key: string): string?
    local value = source[key]
    if typeof(value) == "string" and #value > 0 then
        return value
    end
    return nil
end

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------

--[[
    Watches every ancestor an inheritable attribute could arrive from, so an edit up there
    re-resolves this element.

    `Selector.ancestorChain` decides which ancestors those are -- the walk is defined once,
    over there, and this used to be a second copy of it with its own `isBoundary` beside it.
    The two agreed by coincidence rather than by construction, which is precisely how
    `Elements` came to expand a preset inherited from a ScreenGui that `Query` never saw.

    The whole chain is watched, not only the ancestors that supply a value today: an ancestor
    nearer than the current provider may set `UnrestGroup` tomorrow and has to win the moment
    it does, and the current provider may clear it and hand the answer back to somebody
    further up. The chain is bounded by the first `LayerCollector` and by the service
    boundary, so the connection count is (chain length x 3) and a screen is the widest it can
    ever get.
]]
local function watchAncestors(instance: Instance, maid: Types.Maid, onChanged: () -> ()): ()
    for _, ancestor in Selector.ancestorChain(instance) do
        for _, name in INHERITABLE do
            maid:Add(ancestor:GetAttributeChangedSignal(name):Connect(onChanged))
        end
    end
end

--- The declared preset names, or a phrase saying there are none, for the unknown-preset warning.
local function declaredPresets(): string
    local names = Presets.List()
    if #names == 0 then
        return "none are declared"
    end
    return table.concat(names, ", ")
end

--[[
    Rebuilds `element.Attributes`, `element.Sources` and `element.Preset`, and installs this
    element's watches on the chain above it into `maid`.

    Not a merge of three layers any more: every key is asked of `Selector.attributeOf`, which
    *is* the three layers -- own, then preset, then the nearest ancestor's, most specific
    winning. `Selector.groupOf` asks the same function, so the group this fills into
    `element.Attributes` is by construction the group `Query({ Group = ... })` matches on.

    Which keys get asked is the union of the attributes the framework reads and whatever the
    preset supplies, so a preset carrying a name outside `WATCHED` still lands in
    `element.Attributes` and still records where it came from.
]]
local function resolve(element: Types.ManagedElement, maid: Types.Maid, onAncestorChanged: () -> ()): ()
    local instance = element.Instance
    local attributes: { [string]: any } = {}
    local sources: { [string]: Types.AttributeSource } = {}

    watchAncestors(instance, maid, onAncestorChanged)

    local presetName, preset, presetFrom = Selector.presetFor(instance)
    element.Preset = if preset ~= nil then presetName else nil

    if presetName ~= nil and preset == nil then
        --[[
            Loud, never fatal. A preset name is data typed by somebody who is not watching the
            output window, and an empty screen is a worse outcome than a warning. The source is
            named because an inherited preset was typed on an ancestor, and that is where the
            fix has to go.
        ]]
        local where = if presetFrom ~= nil then presetFrom.Text else "set here"
        warn(
            `[Unrest.Elements] {instance:GetFullName()} resolves {ATTRIBUTES.Preset} = "{presetName}" `
                .. `({where}), which is not a declared preset. Declared presets: {declaredPresets()}. `
                .. `The element was adopted with its own attributes only -- fix the spelling, or declare `
                .. `it with Presets.Register("{presetName}", ...).`
        )
    end

    local names: { string } = table.clone(WATCHED)
    if preset ~= nil then
        for name in preset do
            -- A preset naming a preset would be a second, invisible level of indirection, and
            -- `attributeOf` refuses to read one; asking again here would only warn twice.
            if name ~= ATTRIBUTES.Preset and table.find(names, name) == nil then
                table.insert(names, name)
            end
        end
    end

    for _, name in names do
        local value, source = Selector.attributeOf(instance, name)
        if value ~= nil and source ~= nil then
            attributes[name] = value
            sources[name] = source
        end
    end

    element.Attributes = attributes
    element.Sources = sources
end

--[[
    One line naming every resolved attribute and the layer it came from:

        UnrestChannel = Example.Status (from preset "PrimaryAction"),
        UnrestGroup = MainMenu (inherited from Menu (ScreenGui)),
        UnrestPayload = Confirm (set here)

    `element.Attributes` says what the element ended up with; this says who decided, which
    is the question a designer actually has when a button does something they never typed.
]]
function Elements.describe(element: Types.ManagedElement): string
    local names: { string } = {}
    for name in element.Attributes do
        table.insert(names, name)
    end
    table.sort(names)

    local parts: { string } = {}
    for _, name in names do
        local source = element.Sources[name]
        local origin = if source ~= nil then source.Text else "set here"
        table.insert(parts, `{name} = {tostring(element.Attributes[name])} ({origin})`)
    end

    if #parts == 0 then
        return "no wiring attributes -- adopted and queryable, nothing more"
    end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Manager
--------------------------------------------------------------------------------

function Elements.new(adapters: Types.AdapterRegistry, bridge: Types.Bridge): Types.ElementManager
    local managed: { [Instance]: Types.ManagedElement } = {}
    --- Lives as long as the adoption: the Destroying hook, the ancestry hook and the
    --- watches on the element's own attributes.
    local adoption: { [Instance]: Types.Maid } = {}
    --- Torn down and rebuilt on every attribute change: the command and channel wiring.
    local wiring: { [Instance]: Types.Maid } = {}
    --- Torn down and rebuilt alongside it: this element's watches on its ancestor chain.
    local ancestry: { [Instance]: Types.Maid } = {}
    --- Adoption order, so `All()` is stable rather than hash-ordered.
    local order: { Instance } = {}
    --[[
        The instances the tag rules brought in -- tagged themselves, or reached by the
        cascade. A hand `:Adopt`ed instance is absent from here and is never released by them,
        so "adopts one instance directly, tag or no tag" stays true.
    ]]
    local byTag: { [Instance]: true } = {}
    --- One `DescendantAdded` per tagged root. The whole live half of the cascade.
    local roots: { [Instance]: Types.Maid } = {}
    --- `UnrestIgnore` watches on the gates `Selector.isGate` names.
    local gates: { [Instance]: Types.Maid } = {}

    local lifetime = Maid.new()
    local started = false
    local destroyed = false

    local managedAdded: Types.Signal<Types.ManagedElement> = Signal.new("Elements.ManagedAdded")
    local managedRemoved: Types.Signal<Types.ManagedElement> = Signal.new("Elements.ManagedRemoved")
    lifetime:Add(managedAdded)
    lifetime:Add(managedRemoved)

    local manager = {
        ManagedAdded = managedAdded,
        ManagedRemoved = managedRemoved,
    }
    local typed = (manager :: any) :: Types.ElementManager

    --[[
        `UnrestCommand` -> the adapter's `Active` event -> `Bridge:Dispatch`.

        `UnrestCooldown` is a client-side debounce and nothing more. It exists so a designer
        can stop a button double-firing on a fat-fingered double click; it is not a rate
        limit, it lives entirely inside this client's memory, and anyone who cares to remove
        it can. The real limit is the per-player budget the server applies on arrival.
    ]]
    local function wireCommand(element: Types.ManagedElement, maid: Types.Maid): ()
        local instance = element.Instance
        local command = readString(element.Attributes, ATTRIBUTES.Command)
        if command == nil then
            return
        end

        local payload = element.Attributes[ATTRIBUTES.Payload]

        local rawCooldown = element.Attributes[ATTRIBUTES.Cooldown]
        local cooldown = if typeof(rawCooldown) == "number" then math.max(rawCooldown, 0) else 0
        local last = -math.huge

        local hint = `Move {ATTRIBUTES.Command} onto an element whose class can be activated `
            .. `(a TextButton, ImageButton, ClickDetector or ProximityPrompt), or remove the attribute.`

        Adapters.bind(adapters, instance, {
            Active = function()
                if cooldown > 0 then
                    local now = os.clock()
                    if now - last < cooldown then
                        return
                    end
                    last = now
                end
                bridge:Dispatch(command, payload)
            end,
        }, maid, hint, true)
    end

    --[[
        `UnrestChannel` -> `Bridge:Subscribe` -> one property of the element.

        The target property is `UnrestBind`, or the adapter's `ValueProperty` when the
        designer did not say (so a TextLabel with only a channel writes its Text, which is
        what they meant). It must be on the adapter's `Bindable` allowlist either way: a
        replicated value is never permitted to write an arbitrary property.
    ]]
    local function wireChannel(element: Types.ManagedElement, maid: Types.Maid): ()
        local instance = element.Instance
        local channel = readString(element.Attributes, ATTRIBUTES.Channel)
        if channel == nil then
            return
        end

        local property = readString(element.Attributes, ATTRIBUTES.Bind) or element.Adapter.ValueProperty
        if property == nil then
            warn(
                `[Unrest.Elements] {instance:GetFullName()} sets {ATTRIBUTES.Channel} = "{channel}" but there is `
                    .. `nothing to write it into: {adapters:Describe(instance)}. `
                    .. `Add {ATTRIBUTES.Bind} = "<property>".`
            )
            return
        end

        if not adapters:CanBind(instance, property) then
            warn(
                `[Unrest.Elements] {instance:GetFullName()} sets {ATTRIBUTES.Bind} = "{property}", which is not `
                    .. `bindable: {adapters:Describe(instance)}. Bindable is an allowlist, so a channel value can `
                    .. `never write an arbitrary property; register an adapter that permits it if you need it.`
            )
            return
        end

        local target = property
        local format = readString(element.Attributes, ATTRIBUTES.Format)
        local writable = instance :: any

        maid:Add(bridge:Subscribe(channel, function(value: any)
            local painted: any = value
            if format ~= nil then
                painted = applyFormat(format, value)
            elseif value == nil then
                -- No Roblox property accepts nil. Without a format there is nothing to write.
                return
            end

            local ok, err = pcall(function()
                writable[target] = painted
            end)
            if not ok then
                warn(
                    `[Unrest.Elements] {instance:GetFullName()} could not write {typeof(painted)} into `
                        .. `{instance.ClassName}.{target} from channel "{channel}": {tostring(err)}. `
                        .. `Add {ATTRIBUTES.Format} to render the value as text, or publish a matching type.`
                )
            end
        end))
    end

    --[[
        Re-runs the whole resolution and rebuilds the wiring from scratch.

        Cleaning the ancestry maid first is what makes a reparent safe: the watches on the
        old chain go before the new chain is walked, so an element that moves holds
        connections to its new ancestors only and an ancestor that stops being one is left
        with nothing attached. A released element clears both maids through the adoption
        maid that owns them, so a destroyed ancestor can never keep this element alive.
    ]]
    local function rewire(element: Types.ManagedElement): ()
        local instance = element.Instance
        local wiringMaid = wiring[instance]
        local ancestryMaid = ancestry[instance]
        if wiringMaid == nil or ancestryMaid == nil then
            return
        end
        wiringMaid:Clean()
        ancestryMaid:Clean()

        resolve(element, ancestryMaid, function()
            rewire(element)
        end)

        element.Role = Selector.roleOf(instance)
        -- The same call `Query` matches with, and the same call adoption made -- so
        -- `element.Group` and `Query({ Group = ... })` are one answer, not two.
        element.Group = Selector.groupOf(instance)

        wireCommand(element, wiringMaid)
        wireChannel(element, wiringMaid)
    end

    --------------------------------------------------------------------------------
    -- The cascade
    --------------------------------------------------------------------------------

    local onIgnoreChanged: (instance: Instance) -> ()

    --[[
        Watches `UnrestIgnore` on an instance the framework does not manage but whose
        attribute still decides what it manages underneath -- a Folder the cascade passes
        through, or the ignored Frame it stopped at. `Selector.isGate` names them.

        Once discovered a gate is kept, even after the tag above it goes away. The set is
        bounded by the shape of the tree rather than by how often tags are edited, and a gate
        whose subtree is no longer managed only ever re-asks a question that answers "nothing
        to do".
    ]]
    local function watchGate(instance: Instance): ()
        if destroyed or gates[instance] ~= nil then
            return
        end

        local maid = Maid.new()
        gates[instance] = maid
        maid:Add(instance:GetAttributeChangedSignal(ATTRIBUTES.Ignore):Connect(function()
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

    --[[
        Adopts or releases one instance according to `Selector.isManaged`.

        Every path that can change coverage ends here, and coverage is *re-derived* rather
        than counted. An element under two tagged ancestors is not held by two references: it
        is asked the question again, and while either ancestor still carries the tag the
        answer is still yes. Nothing has to be decremented in the right order, and no counter
        can drift out of step with the tree it describes.
    ]]
    local function reconcile(instance: Instance): ()
        if destroyed then
            return
        end

        if Selector.isManaged(instance) then
            if typed:Adopt(instance) ~= nil then
                byTag[instance] = true
            end
        elseif byTag[instance] then
            typed:Release(instance)
        end
    end

    --- Adopts everything the cascade reaches under `root`, and watches the gates it reports.
    local function sweep(root: Instance): ()
        local cascaded, gated = Selector.cascadeUnder(root)
        for _, instance in cascaded do
            reconcile(instance)
        end
        for _, instance in gated do
            watchGate(instance)
        end
    end

    --[[
        Re-asks the question for everything managed at or under `root`. Only releases can come
        of it: nothing is adopted by a tag going away or by an `UnrestIgnore` appearing. The
        managed set is walked rather than the tree, so untagging a ScreenGui costs the elements
        it adopted and not the instances it contains.
    ]]
    local function reconcileUnder(root: Instance): ()
        reconcile(root)
        for _, instance in table.clone(order) do
            if instance ~= root and instance:IsDescendantOf(root) then
                reconcile(instance)
            end
        end
    end

    --[[
        `UnrestIgnore` went on or came off. Both directions are the same two steps -- release
        what is now excluded, adopt what is no longer excluded -- because one of them is always
        a no-op and neither needs to know which way the edit went.
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

        if managed[instance] ~= nil then
            -- Adopted again: its own adoption maid carries the watch from here.
            dropGate(instance)
        end
    end

    --[[
        One `DescendantAdded` per tagged root, and nothing per descendant. A GuiObject parented
        into a managed subtree is adopted on arrival -- and so is every GuiObject of a whole
        panel parented in at once, because the signal fires once for each of them.

        There is deliberately no `DescendantRemoving`. Leaving is the element's own news: every
        adopted element already watches `AncestryChanged`, which fires *after* the move with
        the final parent in place, so the question it re-asks has a true answer.
        `DescendantRemoving` fires while the element is still where it was and could only ask
        the question one step too early.
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
            reconcile(instance)
        end))
    end

    local function onTagAdded(root: Instance): ()
        addRoot(root)
        reconcile(root)
        if managed[root] == nil then
            -- Tagged but not adopted -- no adapter matched its class. Its `UnrestIgnore` still
            -- decides what the cascade does underneath, and nothing else is watching it.
            watchGate(root)
        end
        sweep(root)
    end

    local function onTagRemoved(root: Instance): ()
        local maid = roots[root]
        if maid ~= nil then
            roots[root] = nil
            maid:Destroy()
        end
        reconcileUnder(root)
    end

    function manager:Adopt(instance: Instance): Types.ManagedElement?
        if destroyed then
            return nil
        end
        if typeof(instance) ~= "Instance" then
            error(`[Unrest.Elements] :Adopt expects an Instance, got {typeof(instance)}.`, 0)
        end

        local existing = managed[instance]
        if existing ~= nil then
            return existing
        end

        local resolved = adapters:Resolve(instance)
        if resolved == nil then
            warn(
                `[Unrest.Elements] {instance:GetFullName()} is tagged "{Constants.Tag}" but {adapters:Describe(instance)}. `
                    .. `It was not adopted.`
            )
            return nil
        end

        local released: Types.Signal<Types.ManagedElement> = Signal.new("Elements.Released")

        local element: Types.ManagedElement = {
            Instance = instance,
            Adapter = resolved,
            Role = Selector.roleOf(instance),
            Group = Selector.groupOf(instance),
            Attributes = {},
            Sources = {},
            Released = released,
        }

        local adoptionMaid = Maid.new()
        local wiringMaid = Maid.new()
        local ancestryMaid = Maid.new()
        adoptionMaid:Add(wiringMaid)
        adoptionMaid:Add(ancestryMaid)
        adoptionMaid:Add(released)

        managed[instance] = element
        adoption[instance] = adoptionMaid
        wiring[instance] = wiringMaid
        ancestry[instance] = ancestryMaid
        table.insert(order, instance)

        -- Editing an attribute in Studio while the game runs re-wires this element only.
        for _, attribute in WATCHED do
            adoptionMaid:Add(instance:GetAttributeChangedSignal(attribute):Connect(function()
                rewire(element)
            end))
        end
        --[[
            `UnrestIgnore` is structural rather than wiring, so it never joins the merge and
            never re-resolves anything: it decides whether this element is here at all.
        ]]
        adoptionMaid:Add(instance:GetAttributeChangedSignal(ATTRIBUTES.Ignore):Connect(function()
            onIgnoreChanged(instance)
        end))
        --[[
            Moving an element changes which ancestors it inherits from, so the answer has to
            be computed again against the new chain. `AncestryChanged` fires for a move
            anywhere above the element, not only at its own parent, which is exactly the set
            of moves that can change that answer -- dragging a Frame between two ScreenGuis
            re-resolves every managed button inside it.

            It is also the whole release half of the cascade. A move can carry an element out
            of every managed subtree, and coverage is re-asked before rewiring because
            resolving an element against ancestors it no longer has is work with a wrong
            answer at the end of it.
        ]]
        adoptionMaid:Add(instance.AncestryChanged:Connect(function()
            if byTag[instance] and not Selector.isManaged(instance) then
                typed:Release(instance)
                return
            end
            rewire(element)
        end))
        adoptionMaid:Add(instance.Destroying:Connect(function()
            typed:Release(instance)
        end))

        rewire(element)
        managedAdded:Fire(element)

        return element
    end

    function manager:Release(instance: Instance): ()
        local element = managed[instance]
        if element == nil then
            return
        end

        managed[instance] = nil
        wiring[instance] = nil
        ancestry[instance] = nil
        byTag[instance] = nil
        local adoptionMaid = adoption[instance]
        adoption[instance] = nil

        local index = table.find(order, instance)
        if index ~= nil then
            table.remove(order, index)
        end

        -- Announce before tearing down: the maid owns the `Released` signal itself.
        element.Released:Fire(element)
        managedRemoved:Fire(element)

        if adoptionMaid ~= nil then
            adoptionMaid:Destroy()
        end
    end

    function manager:Start(): ()
        if started or destroyed then
            return
        end
        started = true

        --[[
            A tag arriving adopts the instance and sweeps what is under it; a tag leaving
            re-asks the question for everything it was holding up, which releases the
            cascaded elements and leaves alone any still covered by a second tagged ancestor
            or by a tag of their own.
        ]]
        local tag = Constants.Tag
        lifetime:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(onTagAdded))
        lifetime:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(onTagRemoved))

        for _, instance in CollectionService:GetTagged(tag) do
            onTagAdded(instance)
        end
    end

    function manager:Get(instance: Instance): Types.ManagedElement?
        return managed[instance]
    end

    function manager:All(): { Types.ManagedElement }
        local all: { Types.ManagedElement } = {}
        for _, instance in order do
            local element = managed[instance]
            if element ~= nil then
                table.insert(all, element)
            end
        end
        return all
    end

    --[[
        A query is independent of the manager: it sources its own candidates straight from
        CollectionService, so it works before `Start` and keeps working after. Its lifetime
        belongs to whoever created it -- call `:Destroy()` on the handle when the screen it
        serves goes away.
    ]]
    function manager:Query(descriptor: Types.Descriptor, handlers: Types.Handlers?): Types.QueryHandle
        return Query.new(adapters, descriptor, handlers)
    end

    function manager:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        started = false

        for _, instance in table.clone(order) do
            typed:Release(instance)
        end
        table.clear(order)
        table.clear(byTag)

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

return Elements
