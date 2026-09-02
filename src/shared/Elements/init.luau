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
    Zero-code wiring
    ---------------------------------------------------------------------------

    A designer with no Luau at all can build a working button:

        Tag           Unrest
        UnrestCommand "Music.Play"
        UnrestPayload "Lobby"

    and a label that follows framework state:

        Tag           Unrest
        UnrestChannel "Music.NowPlaying"
        UnrestBind    "Text"
        UnrestFormat  "Music: {value}"

    An attribute grants no privilege. `UnrestCommand` goes through the same
    `Bridge:Dispatch` as hand-written Luau, so the command's contract still decides whether
    the request is allowed to happen at all. Adding an attribute in Studio can never widen
    what a client may ask for -- the permission was never in the attribute.

    ---------------------------------------------------------------------------
    Resolution: three layers, most specific wins
    ---------------------------------------------------------------------------

    `element.Attributes` is not a copy of the instance's attributes any more. It is the
    result of merging three layers, weakest first:

        3. inheritance -- the nearest ancestor that sets one of `Constants.Inheritable`;
        2. the preset  -- the bundle named by `UnrestPreset`, from `Presets.luau`;
        1. the element -- whatever the designer set on this instance.

    So a preset is a default and never an override, and an ancestor is a fallback and never
    a mandate. `element.Sources` records which layer won each key, so "who set this?" has an
    answer without reading three places in Studio.

    Only the three names in `Constants.Inheritable` are ever inherited, because the rule is
    *inherit context, never intent*. `UnrestGroup` says which screen an element is on and
    every element on that screen shares the answer; `UnrestCommand` says what this one
    button does, and inheriting it would silently arm every descendant of a panel with the
    same command. Role, command, payload, channel, bind and format are therefore per-element
    and stay that way.

    The walk stops at the first `LayerCollector` -- a screen is the widest thing an
    inheritable attribute is allowed to mean -- and never reads a service or the DataModel,
    because `UnrestGroup` on `Players` would be a global.

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
    "Music: {value}", never "%s". A function replacement is used so a `%` in the value is a
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
    Where the ancestor walk stops climbing.

    The DataModel and the services hanging off it are never read. An inheritable attribute
    is meant to say "everything on this screen belongs to MainMenu"; `UnrestGroup` on
    `Players` or on `StarterGui` would be a global, and a global is the thing this feature
    is not.
]]
local function isBoundary(instance: Instance): boolean
    if instance == game then
        return true
    end
    local parent = instance.Parent
    return parent ~= nil and parent == game
end

--[[
    Walks up from `instance`, returning the nearest ancestor that sets each inheritable
    attribute, and watching every ancestor on the way for changes to all three.

    The whole chain is watched, not only the ancestors that supply a value today: an
    ancestor nearer than the current provider may set `UnrestGroup` tomorrow and has to win
    the moment it does, and the current provider may clear it and hand the answer back to
    somebody further up.

    Two things bound the walk, so the connection count is (chain length x 3) and a screen is
    the widest it can ever get: the first `LayerCollector` (ScreenGui / SurfaceGui /
    BillboardGui), whose own attributes are read before stopping, and the service boundary.
]]
local function collectAncestors(instance: Instance, maid: Types.Maid, onChanged: () -> ()): { [string]: Instance }
    local providers: { [string]: Instance } = {}

    local current: Instance? = instance.Parent
    while current ~= nil do
        local ancestor: Instance = current
        if isBoundary(ancestor) then
            break
        end

        for _, name in INHERITABLE do
            if not providers[name] and ancestor:GetAttribute(name) ~= nil then
                providers[name] = ancestor
            end
            maid:Add(ancestor:GetAttributeChangedSignal(name):Connect(onChanged))
        end

        if ancestor:IsA("LayerCollector") then
            break
        end
        current = ancestor.Parent
    end

    return providers
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
    Rebuilds `element.Attributes`, `element.Sources` and `element.Preset` from the three
    layers, and installs this element's watches on the chain above it into `maid`.

    Applied weakest first, so each layer simply overwrites the one before it and the last
    writer wins: inherited, then preset, then own.
]]
local function resolve(element: Types.ManagedElement, maid: Types.Maid, onAncestorChanged: () -> ()): ()
    local instance = element.Instance
    local attributes: { [string]: any } = {}
    local sources: { [string]: Types.AttributeSource } = {}

    -- Layer 3: the nearest ancestor that sets each inheritable attribute.
    local providers = collectAncestors(instance, maid, onAncestorChanged)
    for name, ancestor in providers do
        attributes[name] = ancestor:GetAttribute(name)
        sources[name] = {
            Origin = "Inherited",
            Ancestor = ancestor,
            Text = `inherited from {ancestor.Name} ({ancestor.ClassName})`,
        }
    end

    --[[
        Layer 2: the preset. `UnrestPreset` is itself inheritable, so a whole screen can be
        given a default bundle from its ScreenGui, but the element's own naming of a preset
        beats the inherited one -- which is why the own value is read before the expansion
        rather than with the rest of layer 1.
    ]]
    local ownPreset = instance:GetAttribute(ATTRIBUTES.Preset)
    if ownPreset ~= nil then
        attributes[ATTRIBUTES.Preset] = ownPreset
        sources[ATTRIBUTES.Preset] = { Origin = "Own", Text = "set here" }
    end

    element.Preset = nil
    local presetName = readString(attributes, ATTRIBUTES.Preset)
    if presetName ~= nil then
        local preset = Presets.Get(presetName)
        if preset == nil then
            --[[
                Loud, never fatal. A preset name is data typed by somebody who is not
                watching the output window, and an empty screen is a worse outcome than a
                warning. The source is named because an inherited preset was typed on an
                ancestor, and that is where the fix has to go.
            ]]
            local from = sources[ATTRIBUTES.Preset]
            local where = if from ~= nil then from.Text else "set here"
            warn(
                `[Unrest.Elements] {instance:GetFullName()} resolves {ATTRIBUTES.Preset} = "{presetName}" `
                    .. `({where}), which is not a declared preset. Declared presets: {declaredPresets()}. `
                    .. `The element was adopted with its own attributes only -- fix the spelling, or declare `
                    .. `it with Presets.Register("{presetName}", ...).`
            )
        else
            element.Preset = presetName
            for name, value in preset do
                -- A preset naming a preset would be a second, invisible level of indirection.
                if name ~= ATTRIBUTES.Preset then
                    attributes[name] = value
                    sources[name] = { Origin = "Preset", Preset = presetName, Text = `from preset "{presetName}"` }
                end
            end
        end
    end

    -- Layer 1: what the designer set on this instance wins outright.
    for _, name in WATCHED do
        local value = instance:GetAttribute(name)
        if value ~= nil then
            attributes[name] = value
            sources[name] = { Origin = "Own", Text = "set here" }
        end
    end

    element.Attributes = attributes
    element.Sources = sources
end

--[[
    One line naming every resolved attribute and the layer it came from:

        UnrestChannel = Music.NowPlaying (from preset "MusicToggle"),
        UnrestGroup = MainMenu (inherited from Menu (ScreenGui)),
        UnrestPayload = Dancefloor (set here)

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
        element.Group = readString(element.Attributes, ATTRIBUTES.Group)

        wireCommand(element, wiringMaid)
        wireChannel(element, wiringMaid)
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
            Moving an element changes which ancestors it inherits from, so the answer has to
            be computed again against the new chain. `AncestryChanged` fires for a move
            anywhere above the element, not only at its own parent, which is exactly the set
            of moves that can change that answer -- dragging a Frame between two ScreenGuis
            re-resolves every managed button inside it.
        ]]
        adoptionMaid:Add(instance.AncestryChanged:Connect(function()
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

        local tag = Constants.Tag
        lifetime:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
            typed:Adopt(instance)
        end))
        lifetime:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
            typed:Release(instance)
        end))

        for _, instance in CollectionService:GetTagged(tag) do
            typed:Adopt(instance)
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

        lifetime:Destroy()
    end

    return typed
end

return Elements
