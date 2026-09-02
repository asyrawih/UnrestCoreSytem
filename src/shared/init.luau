--!strict
--[[
    Unrest -- ReplicatedStorage.Unrest

    Composition root. Requiring this module gives you the singleton for the current runtime
    context (one on the server, one per client); `:Start()` boots it.

    Model / View / Controller, straight off the whiteboard:

        Core (Model)  --publish/command-->  Bridge (Controller)  --query/mount-->  UI (View)

    Core never touches an Instance. UI never touches a system. Everything crosses at the
    Bridge, and `Unrest:Query` / `Unrest:Mount` are just the two shortcuts you reach for most.

    Canonical usage (the board's own sketch, made valid):

        local Unrest = require(ReplicatedStorage.Unrest):Start()

        Unrest:Query({
            Tag = "Unrest",
            Selector = "TextButton", -- is:A("TextButton")
            Name = "ToggleMenu",
        }, {
            Active = function(element) end,
            Hover = function(element) end,
        })
]]

local RunService = game:GetService("RunService")

local Constants = require(script.Constants)
local Types = require(script.Types)

local BridgeFactory = require(script.Bridge)
local CoreFactory = require(script.Core)
local UIFactory = require(script.UI)

local AvatarContext = require(script.Core.Systems.AvatarContext)
local DanceSystem = require(script.Core.Systems.DanceSystem)
local MusicSystem = require(script.Core.Systems.MusicSystem)
local PluginExtended = require(script.Core.Systems.PluginExtended)

local DxChipsX = require(script.UI.Components.DxChipsX)

local bridge = BridgeFactory.new()
local core = CoreFactory.new()
local ui = UIFactory.new(bridge)

local Unrest = {
    Version = Constants.Version,
    Context = (if RunService:IsServer() then "Server" else "Client") :: Types.RuntimeContext,
    Tag = Constants.Tag,

    Core = core,
    Bridge = bridge,
    UI = ui,
}

--- The one cast in the framework: the singleton is only complete once its methods exist.
local singleton = (Unrest :: any) :: Types.Unrest

--------------------------------------------------------------------------------
-- Built-ins. Order here is irrelevant; Core sorts by `Dependencies`.
--------------------------------------------------------------------------------

core:Register(MusicSystem)
core:Register(AvatarContext)
core:Register(DanceSystem)
core:Register(PluginExtended)

ui:Register(DxChipsX)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Boots every registered system: `Init(unrest)` for all, then `Start()` for all.
function Unrest:Start(): Types.Unrest
    core:Start(singleton)
    return singleton
end

function Unrest:Stop(): ()
    core:Stop()
end

function Unrest:IsStarted(): boolean
    return core:IsStarted()
end

--- Registers a Core system. Before `:Start()` it is queued; after, it boots immediately.
function Unrest:Register(definition: Types.System): Types.System
    return core:Register(definition)
end

--[[
    Fetches a system, throwing if it is missing. Cast the result to the system's exported
    type to get autocomplete back:

        local music = Unrest:Get("MusicSystem") :: Types.MusicSystem
]]
function Unrest:Get(name: string): Types.System
    return core:Expect(name)
end

--- Live selector query. See `docs/ARCHITECTURE.md` for the descriptor and handler reference.
function Unrest:Query(descriptor: Types.Descriptor, handlers: Types.Handlers?): Types.QueryHandle
    return bridge:Query(descriptor, handlers)
end

--- Builds a registered component and parents it.
function Unrest:Mount(component: string, props: Types.Props, parent: Instance): Types.ComponentHandle
    return ui:Mount(component, props, parent)
end

return singleton
