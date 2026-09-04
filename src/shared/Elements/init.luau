--!strict
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

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
    element owns hangs off one cleanup scope, so release is one line and cannot half-happen.

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

    Neither the rule nor the bookkeeping is written here. `Selector.isManaged` is the
    predicate and `Selector.cascadeUnder` the enumeration; `Adapters.Cascade` is the ledger
    that keeps those answers live -- the tagged roots, their `DescendantAdded`, the
    `UnrestIgnore` watch per gate, the re-sweeps. `Query` uses the same predicate and the same
    ledger, because an element this manager adopted and wired but a query could not find would
    be worse than an element nobody adopted at all, and two copies of the ledger is exactly
    how that happens.

    What this module supplies the ledger is the half that genuinely differs: cover means
    adopt, uncover means release. When either happens is not its question.

    Coverage is re-derived, never counted: an element covered by two tagged ancestors keeps
    answering yes until both are gone, with no reference count to keep in step with the tree.

    The connection budget, in full: whatever the ledger spends (one `DescendantAdded` per
    tagged root, one `UnrestIgnore` watch per gate) and -- on adopted elements only, which
    already carry a scope -- one more `UnrestIgnore` watch each. Nothing is connected to an
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

    An attribute is not a second mechanism. `UnrestCommand` goes through the same
    `Bridge:Dispatch` as hand-written Luau and reaches the same handlers, so a screen wired
    entirely in Studio and one wired entirely in code are indistinguishable from the far
    side of the Bridge.

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

local Adapters = require(script.Parent.Adapters)
local Cascade = require(script.Parent.Adapters.Cascade)
local Constants = require(script.Parent.Constants)
local Presets = require(script.Parent.Presets)
local Query = require(script.Parent.Adapters.Query)
local Scope = require(script.Parent.Util.Scope)
local Selector = require(script.Parent.Adapters.Selector)
local Signal = require(script.Parent.Util.Signal)
local Types = require(script.Parent.Types)

local Elements = {}

local ATTRIBUTES = Constants.Attributes

--[[
    Built once at load rather than per rewire. It is a constant sentence, and it was being
    assembled for every element carrying an `UnrestCommand` on every rewire, to be read only
    if the bind was refused.
]]
local COMMAND_HINT = `Move {Constants.Attributes.Command} onto an element whose class can be activated `
    .. `(a TextButton, ImageButton, ClickDetector or ProximityPrompt), or remove the attribute.`

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
    "Status: {value}", never "%s".

    Split once, at wire time, into what goes before the hole and what goes after. Painting is
    then two concatenations. It used to run `string.gsub` with a *function* replacement -- so a
    per cent sign in the value stayed a per cent sign rather than becoming a gsub escape -- but
    that allocated a closure and ran the pattern matcher on every published value, on every
    element bound to the channel. Splitting keeps the same guarantee for free: neither half is
    ever re-scanned, so nothing in the value can be read as a pattern.

    A template with no `{value}` in it is a constant, and `suffix` being nil is how that is
    remembered. A second `{value}` is left alone: the first hole is the hole.
]]
local function splitFormat(format: string): (string, string?)
    local start, finish = string.find(format, "{value}", 1, true)
    if start == nil or finish == nil then
        return format, nil
    end
    return string.sub(format, 1, start - 1), string.sub(format, finish + 1)
end

local function applyFormat(prefix: string, suffix: string?, value: any): string
    if suffix == nil then
        return prefix
    end
    local text = if value == nil then "" else tostring(value)
    return prefix .. text .. suffix
end

--[[
    Hoisted so `pcall` can be handed a function and its arguments instead of a closure that
    captures them. Luau forwards varargs to `pcall` without allocating, and this runs once per
    published value per bound element -- the one place in the framework that can be reached at
    a frame's cadence.
]]
local function assign(container: any, key: string, value: any): ()
    container[key] = value
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
local function watchAncestors(instance: Instance, scope: Types.Scope, onChanged: () -> ()): ()
    for _, ancestor in Selector.ancestorChain(instance) do
        for _, name in INHERITABLE do
            Scope.add(scope, ancestor:GetAttributeChangedSignal(name):Connect(onChanged))
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
    element's watches on the chain above it into `scope`.

    Not a merge of three layers any more: every key is asked of `Selector.attributeIn`, which
    *is* the three layers -- own, then preset, then the nearest ancestor's, most specific
    winning. `Selector.groupOf` asks the same function, so the group this fills into
    `element.Attributes` is by construction the group `Query({ Group = ... })` matches on.

    The ancestor walk and the preset lookup are gathered ONCE, into a `Selector.Resolution`,
    and every key is then answered out of it. Asking `Selector.attributeOf` per key meant a
    fresh walk to the ScreenGui per key -- fifteen of them for the nine keys here, every time
    any watched attribute anywhere above or on the element was edited.

    Which keys get asked is the union of the attributes the framework reads and whatever the
    preset supplies, so a preset carrying a name outside `WATCHED` still lands in
    `element.Attributes` and still records where it came from.
]]
local function resolve(
    element: Types.ManagedElement,
    scope: Types.Scope,
    onAncestorChanged: () -> ()
): Selector.Resolution
    local instance = element.Instance
    local attributes: { [string]: any } = {}
    local sources: { [string]: Types.AttributeSource } = {}

    watchAncestors(instance, scope, onAncestorChanged)

    local resolved = Selector.resolution(instance)
    local presetName, preset, presetFrom = resolved.PresetName, resolved.Preset, resolved.PresetSource
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
            -- `attributeIn` refuses to read one; asking again here would only warn twice.
            if name ~= ATTRIBUTES.Preset and table.find(names, name) == nil then
                table.insert(names, name)
            end
        end
    end

    for _, name in names do
        local value, source = Selector.attributeIn(resolved, name)
        if value ~= nil and source ~= nil then
            attributes[name] = value
            sources[name] = source
        end
    end

    element.Attributes = attributes
    element.Sources = sources

    --[[
        Handed back so the caller can finish the element out of the same snapshot. `element.Group`
        is the next thing asked, and asking `Selector.groupOf` for it would walk the tree again
        to re-derive what this resolution is already holding.
    ]]
    return resolved
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
    local adoption: { [Instance]: Types.Scope } = {}
    --- Torn down and rebuilt on every attribute change: the command and channel wiring.
    local wiring: { [Instance]: Types.Scope } = {}
    --- Torn down and rebuilt alongside it: this element's watches on its ancestor chain.
    local ancestry: { [Instance]: Types.Scope } = {}
    --[[
        One `() -> ()` per element that re-runs its wiring. `Adopt` makes it, every watch it
        installs shares it, and `rewire` hands the same one to each ancestor watch `resolve`
        adds -- so an element pays for it once rather than once per watched attribute, and
        again on every rewire.
    ]]
    local rewires: { [Instance]: () -> () } = {}
    --- Adoption order, so `All()` is stable rather than hash-ordered.
    local order: { Instance } = {}
    --[[
        The instances the tag rules brought in -- tagged themselves, or reached by the
        cascade. A hand `:Adopt`ed instance is absent from here and is never released by them,
        so "adopts one instance directly, tag or no tag" stays true.
    ]]
    local byTag: { [Instance]: true } = {}

    local lifetime = Scope.scope()
    local started = false
    local destroyed = false

    local managedAdded: Types.Signal<Types.ManagedElement> = Signal.new("Elements.ManagedAdded")
    local managedRemoved: Types.Signal<Types.ManagedElement> = Signal.new("Elements.ManagedRemoved")
    Scope.addBulk(lifetime, managedAdded, managedRemoved)

    local manager = {
        ManagedAdded = managedAdded,
        ManagedRemoved = managedRemoved,
    }
    local typed = (manager :: any) :: Types.ElementManager

    --[[
        `UnrestCommand` -> the adapter's `Active` event -> `Bridge:Dispatch`.

        `UnrestCooldown` is a debounce and nothing more. It exists so a designer can stop a
        button double-firing on a fat-fingered double click; it lives entirely in this
        element's memory and is forgotten when the element is released.
    ]]
    local function wireCommand(element: Types.ManagedElement, scope: Types.Scope): ()
        local instance = element.Instance
        local command = readString(element.Attributes, ATTRIBUTES.Command)
        if command == nil then
            return
        end

        local payload = element.Attributes[ATTRIBUTES.Payload]

        local rawCooldown = element.Attributes[ATTRIBUTES.Cooldown]
        local cooldown = if typeof(rawCooldown) == "number" then math.max(rawCooldown, 0) else 0
        local last = -math.huge

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
        }, scope, COMMAND_HINT, true)
    end

    --[[
        `UnrestChannel` -> `Bridge:Subscribe` -> one property of the element.

        The target property is `UnrestBind`, or the adapter's `ValueProperty` when the
        designer did not say (so a TextLabel with only a channel writes its Text, which is
        what they meant). It must be on the adapter's `Bindable` allowlist either way: a
        published value is never permitted to write an arbitrary property.
    ]]
    local function wireChannel(element: Types.ManagedElement, scope: Types.Scope): ()
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
        local prefix: string?, suffix: string? = nil, nil
        if format ~= nil then
            prefix, suffix = splitFormat(format)
        end
        local writable = instance :: any

        Scope.add(
            scope,
            bridge:Subscribe(channel, function(value: any)
                local painted: any = value
                if prefix ~= nil then
                    painted = applyFormat(prefix :: string, suffix, value)
                elseif value == nil then
                    -- No Roblox property accepts nil. Without a format there is nothing to write.
                    return
                end

                --[[
                    `assign` is cast because `pcall` is typed from the callee's returns, and a
                    function declared `-> ()` makes the checker insist `pcall` yields only the
                    boolean. It always yields the error as well when the call fails, which is
                    the value being read here.
                ]]
                local ok, err = pcall(assign :: any, writable, target, painted)
                if not ok then
                    warn(
                        `[Unrest.Elements] {instance:GetFullName()} could not write {typeof(painted)} into `
                            .. `{instance.ClassName}.{target} from channel "{channel}": {tostring(err)}. `
                            .. `Add {ATTRIBUTES.Format} to render the value as text, or publish a matching type.`
                    )
                end
            end)
        )
    end

    --[[
        Re-runs the whole resolution and rebuilds the wiring from scratch.

        Cleaning the ancestry scope first is what makes a reparent safe: the watches on the
        old chain go before the new chain is walked, so an element that moves holds
        connections to its new ancestors only and an ancestor that stops being one is left
        with nothing attached. A released element clears both scopes through the adoption
        scope that owns them, so a destroyed ancestor can never keep this element alive.
    ]]
    local function rewire(element: Types.ManagedElement): ()
        local instance = element.Instance
        local wiringScope = wiring[instance]
        local ancestryScope = ancestry[instance]
        local onAncestorChanged = rewires[instance]
        if wiringScope == nil or ancestryScope == nil or onAncestorChanged == nil then
            return
        end
        Scope.clean(wiringScope)
        Scope.clean(ancestryScope)

        local resolved = resolve(element, ancestryScope, onAncestorChanged)

        element.Role = Selector.roleOf(instance)
        --[[
            Read out of the resolution `resolve` just built, not re-derived. It is the same
            precedence `Query` matches with -- `Selector.groupIn` is what `Selector.groupOf`
            calls -- so `element.Group` and `Query({ Group = ... })` remain one answer.
        ]]
        element.Group = Selector.groupIn(resolved)

        wireCommand(element, wiringScope)
        wireChannel(element, wiringScope)
    end

    --------------------------------------------------------------------------------
    -- The cascade
    --------------------------------------------------------------------------------

    --[[
        The ledger `Query` also uses. It decides *when* an instance is covered; adopting and
        releasing is what this manager does about it.

        `Uncover` releases only what the tag rules brought in. A hand `:Adopt`ed instance is
        absent from `byTag` and survives a tag going away, so "adopts one instance directly,
        tag or no tag" stays true. `Cover` records the ones that stick: an `:Adopt` can decline
        (no adapter matched the class), and a tagged Folder that was never adopted is a gate
        the ledger keeps watching rather than an element this manager holds.
    ]]
    local cascade = Cascade.new({
        Cover = function(instance: Instance): ()
            if destroyed then
                return
            end
            if typed:Adopt(instance) ~= nil then
                byTag[instance] = true
            end
        end,
        Uncover = function(instance: Instance): ()
            if destroyed then
                return
            end
            if byTag[instance] then
                typed:Release(instance)
            end
        end,
        Tracks = function(instance: Instance): boolean
            return managed[instance] ~= nil
        end,
        --- Adoption order, so a release sweep runs in the order `All()` reports.
        Covered = function(): { Instance }
            return table.clone(order)
        end,
    })
    Scope.add(lifetime, cascade)

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

        local adoptionScope = Scope.scope()
        local wiringScope = Scope.scope()
        local ancestryScope = Scope.scope()
        Scope.addBulk(adoptionScope, wiringScope, ancestryScope, released)

        --[[
            The one closure that re-runs this element's wiring, made here and nowhere else.

            Every watch below wants it, `resolve` hands it to each of the ancestor watches it
            installs, and all of them want the same two lines. Written inline it was a fresh
            closure per watched attribute per element -- nine before anything else -- and
            another one on every rewire thereafter.
        ]]
        local function rewireThis(): ()
            rewire(element)
        end

        managed[instance] = element
        adoption[instance] = adoptionScope
        wiring[instance] = wiringScope
        ancestry[instance] = ancestryScope
        rewires[instance] = rewireThis
        table.insert(order, instance)

        -- Editing an attribute in Studio while the game runs re-wires this element only.
        for _, attribute in WATCHED do
            Scope.add(adoptionScope, instance:GetAttributeChangedSignal(attribute):Connect(rewireThis))
        end
        --[[
            `UnrestIgnore` is structural rather than wiring, so it never joins the merge and
            never re-resolves anything: it decides whether this element is here at all.
        ]]
        Scope.add(
            adoptionScope,
            instance:GetAttributeChangedSignal(ATTRIBUTES.Ignore):Connect(function()
                cascade:IgnoreChanged(instance)
            end)
        )
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
        Scope.add(
            adoptionScope,
            instance.AncestryChanged:Connect(function()
                if byTag[instance] and not Selector.isManaged(instance) then
                    typed:Release(instance)
                    return
                end
                rewireThis()
            end)
        )
        Scope.add(
            adoptionScope,
            instance.Destroying:Connect(function()
                typed:Release(instance)
            end)
        )

        rewireThis()
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
        rewires[instance] = nil
        byTag[instance] = nil
        local adoptionScope = adoption[instance]
        adoption[instance] = nil

        local index = table.find(order, instance)
        if index ~= nil then
            table.remove(order, index)
        end

        -- Announce before tearing down: the scope owns the `Released` signal itself.
        element.Released:Fire(element)
        managedRemoved:Fire(element)

        if adoptionScope ~= nil then
            Scope.destroy(adoptionScope)
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
        cascade:Source(Constants.Tag)
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

    --[[
        Why one instance does or does not match a descriptor, clause by clause.

        The door onto `Selector.explain`, which is where the sentence is built -- the same
        predicate the query filters on answers the question, so an explanation cannot say
        `ok` about a clause the match rejected. A query that comes back empty says only that;
        this says which of the five conditions turned an instance away, and what it actually is.
    ]]
    function manager:Explain(descriptor: Types.Descriptor, instance: Instance): string
        return Selector.explain(descriptor, instance)
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

        Scope.destroy(lifetime)
    end

    return typed
end

return Elements
