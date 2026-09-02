--!strict
--[[
    Unrest / Adapters

    The AdapterRegistry: per-ClassName knowledge about Roblox UI, and the one place that
    knows how to attach a handler table to an instance.

    The framework builds no UI, so it cannot know what an element can do by having made it.
    An *adapter* is that knowledge, written down once per class: which Roblox events back
    the framework's handler vocabulary, and which properties a channel value is allowed to
    write. Adapters compose along the real class hierarchy through `Extends`, so
    `TextButton` inherits everything `GuiButton`, `GuiObject` and `GuiBase2d` already taught.

    Resolution answers "what is this instance?" in two steps:

      1. pick the most specific *registered* adapter the instance `:IsA()`. An exact
         ClassName match wins outright; otherwise the candidate whose `Extends` chain
         contains the incumbent wins, which is how a `UIDragDetector` the framework has
         never heard of still resolves usefully to `UIComponent`;
      2. flatten that adapter's chain into one table, derived-wins, and cache the result
         under the instance's ClassName so the walk happens once per class per session.

    `Bindable` is an allowlist and not a denylist, deliberately. A channel value arriving
    from the server must never be able to write an arbitrary property of an arbitrary
    instance; `UnrestBind = "Parent"` is not a clever trick, it is a rejected attribute.

    `Register` is public: a custom class, or a house style that wants `UIStroke.Thickness`
    bindable when the built-in adapter does not, is one call away at runtime.
]]

local Buttons = require(script.Classes.Buttons)
local Frames = require(script.Classes.Frames)
local GuiBase = require(script.Classes.GuiBase)
local Interaction = require(script.Classes.Interaction)
local LayerCollectors = require(script.Classes.LayerCollectors)
local Primitives = require(script.Parent.Primitives)
local Resolver = require(script.Parent.Util.Resolver)
local Signal = require(script.Parent.Util.Signal)
local Text = require(script.Classes.Text)
local Types = require(script.Types)
local UIComponents = require(script.Classes.UIComponents)

local Adapters = {}

--[[
    `Added` and `Removed` describe the *query's* lifecycle, not the element's, so they are
    never looked up in an adapter's event table. Every element supports them, including the
    ones that support nothing else.
]]
local LIFECYCLE: { [string]: boolean } = {
    Added = true,
    Removed = true,
}

--- Registration order matters only in that a base should exist before what extends it,
--- otherwise the chain warns and stops short. Bases first, therefore.
local FAMILIES: { { Types.Adapter } } = {
    GuiBase,
    Buttons,
    Text,
    Frames,
    LayerCollectors,
    UIComponents,
    Interaction,
}

--- Sorted, `false` entries dropped, for stable error messages.
local function sortedKeys(source: { [string]: any }): { string }
    local keys: { string } = {}
    for key, value in source do
        if value ~= false then
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    return keys
end

local function listOrNone(keys: { string }): string
    if #keys == 0 then
        return "none"
    end
    return table.concat(keys, ", ")
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

function Adapters.new(): Types.AdapterRegistry
    local registered: { [string]: Types.Adapter } = {}
    --- Flattened adapter, keyed by the *adapter's* ClassName.
    local flattened: { [string]: Types.ResolvedAdapter } = {}
    --- Flattened adapter, keyed by the *instance's* ClassName. The hot path.
    local resolvedFor: { [string]: Types.ResolvedAdapter } = {}
    --- Instance ClassNames known to have no adapter at all, so the walk is not repeated.
    local unresolvable: { [string]: boolean } = {}
    --- One warning per broken `Extends` link, not one per resolve.
    local warned: { [string]: boolean } = {}

    local adapterAdded: Primitives.Signal<Types.Adapter> = Signal.new("Adapters.AdapterAdded")

    local registry = {
        AdapterAdded = adapterAdded,
    }
    local typed = (registry :: any) :: Types.AdapterRegistry

    --- Most specific first: { "TextButton", "GuiButton", "GuiObject", "GuiBase2d" }.
    local function chainOf(className: string): { string }
        local chain: { string } = {}
        local seen: { [string]: boolean } = {}
        local current: string? = className

        while current ~= nil and not seen[current] do
            local adapter = registered[current]
            if adapter == nil then
                local from = if #chain > 0 then chain[#chain] else "<root>"
                local key = `{from}->{current}`
                if not warned[key] then
                    warned[key] = true
                    warn(
                        `[Unrest.Adapters] adapter "{from}" extends "{current}", which is not registered. `
                            .. `The chain stops there, so anything "{current}" would have contributed is missing. `
                            .. `Register the base adapter before the one that extends it.`
                    )
                end
                break
            end

            seen[current] = true
            table.insert(chain, current)
            current = adapter.Extends
        end

        return chain
    end

    local function flatten(className: string): Types.ResolvedAdapter
        local cached = flattened[className]
        if cached ~= nil then
            return cached
        end

        local chain = chainOf(className)
        local events: { [string]: Types.EventBinder } = {}
        local bindable: { [string]: boolean } = {}
        local valueProperty: string? = nil

        -- Least specific first so a derived adapter overwrites what it inherited.
        for index = #chain, 1, -1 do
            local adapter = registered[chain[index]]

            local adapterEvents = adapter.Events
            if adapterEvents ~= nil then
                for key, binder in adapterEvents do
                    events[key] = binder
                end
            end

            local adapterBindable = adapter.Bindable
            if adapterBindable ~= nil then
                for key, allowed in adapterBindable do
                    bindable[key] = allowed
                end
            end

            if adapter.ValueProperty ~= nil then
                valueProperty = adapter.ValueProperty
            end
        end

        --[[
            `Changed` is synthesised rather than written by hand. An adapter that declares
            `ValueProperty = "Text"` has already said everything needed to watch it, and
            asking every author to repeat the same GetPropertyChangedSignal is how the two
            drift apart. An adapter may still declare its own `Changed` binder, and that
            one wins.
        ]]
        local property = valueProperty
        if property ~= nil and events.Changed == nil then
            events.Changed = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
                return element:GetPropertyChangedSignal(property):Connect(function()
                    invoke((element :: any)[property])
                end)
            end
        end

        local resolved: Types.ResolvedAdapter = {
            ClassName = className,
            Chain = chain,
            Events = events,
            Bindable = bindable,
            ValueProperty = valueProperty,
        }
        flattened[className] = resolved
        return resolved
    end

    --- True when `candidate` derives from `incumbent`, i.e. it is the more specific of the two.
    local function derivesFrom(candidate: string, incumbent: string): boolean
        for _, name in chainOf(candidate) do
            if name == incumbent then
                return true
            end
        end
        return false
    end

    function registry:Register(adapter: Types.Adapter): Types.Adapter
        local validated = Resolver.Adapter(adapter)

        registered[validated.ClassName] = validated

        --[[
            A new adapter can change what any class resolves to -- registering `GuiButton`
            re-parents every TextButton's chain -- so the caches go rather than trying to
            work out which entries are still valid. Registration is rare; resolution is not.
        ]]
        table.clear(flattened)
        table.clear(resolvedFor)
        table.clear(unresolvable)

        adapterAdded:Fire(validated)
        return validated
    end

    function registry:Resolve(instance: Instance): Types.ResolvedAdapter?
        if typeof(instance) ~= "Instance" then
            error(`[Unrest.Adapters] :Resolve expects an Instance, got {typeof(instance)}.`, 0)
        end

        local key = instance.ClassName
        local cached = resolvedFor[key]
        if cached ~= nil then
            return cached
        end
        if unresolvable[key] then
            return nil
        end

        local best: string? = if registered[key] ~= nil then key else nil
        if best == nil then
            for className in registered do
                if not instance:IsA(className) then
                    continue
                end

                local incumbent = best
                if incumbent == nil or derivesFrom(className, incumbent) then
                    best = className
                elseif not derivesFrom(incumbent, className) then
                    --[[
                        Two adapters match and neither derives from the other, which only
                        happens when a custom adapter is registered against a class the
                        built-ins already cover from a different angle. Deeper chain wins,
                        then alphabetical -- arbitrary, but stable, and stable beats
                        "depends on hash order" every time.
                    ]]
                    local depth, held = #chainOf(className), #chainOf(incumbent)
                    if depth > held or (depth == held and className < incumbent) then
                        best = className
                    end
                end
            end
        end

        if best == nil then
            unresolvable[key] = true
            return nil
        end

        local resolved = flatten(best)
        resolvedFor[key] = resolved
        return resolved
    end

    function registry:Supports(instance: Instance, handler: string): boolean
        if LIFECYCLE[handler] then
            return true
        end
        local resolved = typed:Resolve(instance)
        return resolved ~= nil and resolved.Events[handler] ~= nil
    end

    function registry:CanBind(instance: Instance, property: string): boolean
        local resolved = typed:Resolve(instance)
        return resolved ~= nil and resolved.Bindable[property] == true
    end

    function registry:Describe(instance: Instance): string
        local resolved = typed:Resolve(instance)
        if resolved == nil then
            return `a {instance.ClassName} has no Unrest adapter at all `
                .. `(registered classes: {listOrNone(typed:List())}). `
                .. `Register one with Unrest.Adapters:Register, giving it ClassName = "{instance.ClassName}" `
                .. `and an Extends naming the closest class the framework already knows.`
        end

        local events = listOrNone(sortedKeys(resolved.Events))
        local properties = listOrNone(sortedKeys(resolved.Bindable))
        return `a {instance.ClassName} resolves to {table.concat(resolved.Chain, " <- ")} `
            .. `and supports handlers: {events} -- bindable properties: {properties}`
    end

    function registry:List(): { string }
        return sortedKeys(registered)
    end

    for _, family in FAMILIES do
        for _, adapter in family do
            typed:Register(adapter)
        end
    end

    return typed
end

--------------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------------

--[[
    The one sentence a refusal is worded as. `bind` raises it, `rejects` returns it and the
    soft path warns it -- three callers, one wording, because being told two different
    stories about one refusal is worse than being told either of them.
]]
local function refusal(registry: Types.AdapterRegistry, element: Instance, key: string, hint: string): string
    return `[Unrest.Adapters] handler "{key}" cannot bind to {element:GetFullName()}: `
        .. `{registry:Describe(element)}. {hint}`
end

--[[
    Why `element` cannot take `handlers`, worded exactly as `bind` would raise it, or `nil`
    when every handler in the table binds.

    Public because asking *before* anything has been touched is the only way a caller can stay
    atomic across more than one element. `QueryHandle:Bind` asks this of every element it
    holds before it merges a new handler table in, so a table that one element cannot honour
    leaves the query exactly as it was instead of half rebuilt around a handler that raises.

    Which unsupported handler it names is whichever the hash order reaches first -- the same
    arbitrary pick `bind` makes, and there is only ever one message either way.
]]
function Adapters.rejects(
    registry: Types.AdapterRegistry,
    element: Instance,
    handlers: Types.Handlers,
    hint: string
): string?
    for key in handlers :: { [string]: Types.ElementHandler } do
        if LIFECYCLE[key] then
            continue
        end
        if not registry:Supports(element, key) then
            return refusal(registry, element, key, hint)
        end
    end
    return nil
end

--[[
    Attaches a handler table to one element and parks the connections in `maid`.

    Shared by the query engine and the ElementManager so that "a Frame cannot Submit" is
    decided in exactly one place, whether the handler came from Luau or from an attribute.

    `hint` is appended to the failure message and should say what the caller can change.
    `soft` downgrades that failure from an error to a warning: code that binds a handler its
    element cannot support is a bug and should stop, whereas a *designer* who typed the
    wrong attribute should not take the rest of the screen down with them.

    The two severities also differ in how much they finish. Raising is **all or nothing**: the
    whole table is checked before a single connection is made, so an element that cannot take
    one handler is left holding none of them rather than the handful that happened to come
    first out of the hash order. Callers lean on that -- `Query` records an element only once
    `bind` has returned, which is only safe while a raise means nothing was wired. Warning is
    deliberately the opposite: the unsupported name is skipped and the rest of the table still
    binds, because not taking the screen down over one mistyped attribute is the whole point.
]]
function Adapters.bind(
    registry: Types.AdapterRegistry,
    element: Instance,
    handlers: Types.Handlers,
    maid: Primitives.Maid,
    hint: string,
    soft: boolean?
): ()
    if not soft then
        local rejection = Adapters.rejects(registry, element, handlers, hint)
        if rejection ~= nil then
            error(rejection, 0)
        end
    end

    local resolved = registry:Resolve(element)

    for key, handler in handlers :: { [string]: Types.ElementHandler } do
        if LIFECYCLE[key] then
            continue
        end

        local binder = if resolved ~= nil then resolved.Events[key] else nil
        if binder == nil then
            -- Only reachable in soft mode: the pre-flight above has already raised otherwise.
            local message = refusal(registry, element, key, hint)
            if soft then
                warn(message)
                continue
            end
            error(message, 0)
        end

        local connection = binder(element, function(value: any)
            handler(element, value)
        end)
        if connection ~= nil then
            maid:Add(connection)
        end
    end
end

return Adapters
