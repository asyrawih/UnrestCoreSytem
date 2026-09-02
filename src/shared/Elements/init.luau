--!strict
--[[
    Unrest / Elements

    Adoption. The half of the framework that turns Studio-built UI into framework UI without
    the framework ever having created a single GuiObject.

    The whole opt-in is one CollectionService tag. Tagging an instance `Unrest` means:

      * an adapter is resolved for its ClassName, so the framework knows what it can do;
      * its `Unrest*` attributes are read and wired, live -- editing one in Studio while the
        game runs re-wires that element and nothing else;
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
    Loud vs. fatal
    ---------------------------------------------------------------------------

    Code that binds a handler its element cannot support is a bug, and `Unrest:Query` throws.
    An attribute that asks for the same thing is *data*, usually typed by somebody who is
    not looking at the output window, and taking the rest of the screen down with it would
    be a worse outcome than a warning naming the element, its class and what that class
    actually supports. So attribute wiring warns and skips; code binding raises.
]]

local CollectionService = game:GetService("CollectionService")

local Adapters = require(script.Parent.Adapters)
local Constants = require(script.Parent.Constants)
local Maid = require(script.Parent.Util.Maid)
local Query = require(script.Parent.Adapters.Query)
local Selector = require(script.Parent.Adapters.Selector)
local Signal = require(script.Parent.Util.Signal)
local Types = require(script.Parent.Types)

local Elements = {}

local ATTRIBUTES = Constants.Attributes

--- Every attribute the manager reacts to, so one loop wires all the change signals.
local WATCHED: { string } = {
    ATTRIBUTES.Role,
    ATTRIBUTES.Group,
    ATTRIBUTES.Command,
    ATTRIBUTES.Payload,
    ATTRIBUTES.Channel,
    ATTRIBUTES.Bind,
    ATTRIBUTES.Format,
    ATTRIBUTES.Cooldown,
}

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
-- Manager
--------------------------------------------------------------------------------

function Elements.new(adapters: Types.AdapterRegistry, bridge: Types.Bridge): Types.ElementManager
    local managed: { [Instance]: Types.ManagedElement } = {}
    --- Lives as long as the adoption: the Destroying hook and the attribute watches.
    local adoption: { [Instance]: Types.Maid } = {}
    --- Torn down and rebuilt on every attribute change: the command and channel wiring.
    local wiring: { [Instance]: Types.Maid } = {}
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

    local function snapshot(instance: Instance): { [string]: any }
        local attributes: { [string]: any } = {}
        for _, name in WATCHED do
            attributes[name] = instance:GetAttribute(name)
        end
        return attributes
    end

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

    --- Re-reads every `Unrest*` attribute and rebuilds the wiring from scratch.
    local function rewire(element: Types.ManagedElement): ()
        local maid = wiring[element.Instance]
        if maid == nil then
            return
        end
        maid:Clean()

        element.Attributes = snapshot(element.Instance)
        element.Role = Selector.roleOf(element.Instance)
        element.Group = Selector.groupOf(element.Instance)

        wireCommand(element, maid)
        wireChannel(element, maid)
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
            Released = released,
        }

        local adoptionMaid = Maid.new()
        local wiringMaid = Maid.new()
        adoptionMaid:Add(wiringMaid)
        adoptionMaid:Add(released)

        managed[instance] = element
        adoption[instance] = adoptionMaid
        wiring[instance] = wiringMaid
        table.insert(order, instance)

        -- Editing an attribute in Studio while the game runs re-wires this element only.
        for _, attribute in WATCHED do
            adoptionMaid:Add(instance:GetAttributeChangedSignal(attribute):Connect(function()
                rewire(element)
            end))
        end
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
