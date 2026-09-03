--!strict
--[[
    Unrest -- ReplicatedStorage.Unrest

    Composition root. Requiring this module gives you the singleton for the current runtime
    context (one on the server, one per client); `:Start()` boots it.

    Model / View / Controller, straight off the whiteboard:

        Core (Model)  --publish/command-->  Bridge (Controller)  --query-->  Studio UI (View)

    One rule makes the rest of the framework fall out: THE FRAMEWORK BUILDS NO UI. Every
    element is made by hand in Studio. Tagging it `Unrest` is the entire opt-in -- the element
    is adopted, an adapter is resolved for its ClassName, its `Unrest*` attributes are wired,
    and it becomes queryable.

    Canonical usage, the board's own sketch made valid:

        local Unrest = require(ReplicatedStorage.Unrest):Start()

        Unrest:Query({
            Tag = "Unrest",
            Selector = "TextButton", -- is:A("TextButton")
            Role = "ToggleMenu",
        }, {
            Active = function(element) Unrest:Dispatch("Example.Action", "Confirm") end,
            Hover = function(element) end,
        })
]]

local RunService = game:GetService("RunService")

local Constants = require(script.Constants)
local Scope = require(script.Util.Scope)
local Types = require(script.Types)

local AdaptersFactory = require(script.Adapters)
local BridgeFactory = require(script.Bridge)
local CoreFactory = require(script.Core)
local ElementsFactory = require(script.Elements)
local WidgetsFactory = require(script.Widgets)

local context: Types.RuntimeContext = if RunService:IsServer() then "Server" else "Client"

--[[
    Construction order is a dependency chain, not a preference:
      Bridge   owns the command/channel bus and needs nothing else;
      Adapters is pure per-class knowledge;
      Elements adopts Studio UI, so it needs an adapter registry to resolve classes with
               and a Bridge to route `UnrestCommand` attributes through;
      Widgets  groups adopted elements into controls, so it needs Elements to query through.
    Nothing points back up, so there is no cycle to break.
]]
local bridge = BridgeFactory.new(context)
local adapters = AdaptersFactory.new()
local elements = ElementsFactory.new(adapters, bridge)
local widgets = WidgetsFactory.new(elements, Constants.Tag, context)
local core = CoreFactory.new()

local Unrest = {
    Version = Constants.Version,
    Context = context,
    Tag = Constants.Tag,

    Core = core,
    Bridge = bridge,
    Adapters = adapters,
    Elements = elements,
    Widgets = widgets,
    Scope = Scope,
}

--- The one cast in the framework: the singleton is only complete once its methods exist.
local singleton = (Unrest :: any) :: Types.Unrest

local started = false

function Unrest:Start(): Types.Unrest
    if started then
        return singleton
    end
    started = true

    --[[
        Adoption is client-only. A tagged ScreenGui does exist on the server, but binding its
        events there would be both useless and misleading: the server has no screen, and no
        player ever clicked anything on it.
    ]]
    if context == "Client" then
        elements:Start()
    end

    core:Start(singleton)
    return singleton
end

function Unrest:Stop(): ()
    if not started then
        return
    end
    started = false
    core:Stop()
end

function Unrest:IsStarted(): boolean
    return started
end

function Unrest:Register(definition: Types.System): Types.System
    return core:Register(definition)
end

function Unrest:Get(name: string): Types.System
    return core:Expect(name)
end

function Unrest:Query(descriptor: Types.Descriptor, handlers: Types.Handlers?): Types.QueryHandle
    return elements:Query(descriptor, handlers)
end

function Unrest:Dispatch(command: string, payload: any): ()
    bridge:Dispatch(command, payload)
end

return singleton
