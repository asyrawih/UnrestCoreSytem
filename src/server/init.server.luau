--!strict
--[[
    UnrestServer -- ServerScriptService.UnrestServer

    Server bootstrap. The same singleton module runs here, in its own runtime context, with
    its own Core, Bridge and UI registry (the UI registry simply goes unused on the server).

    It also demonstrates "Plugin Extended": a system that lives entirely outside the
    framework, registered at runtime, participating in the ordinary dependency graph.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--------------------------------------------------------------------------------
-- Plugin Extended: a third-party system, registered after startup.
--------------------------------------------------------------------------------

local plugins = unrest:Get("PluginExtended") :: Types.PluginExtended

--[[
    A plugin is nothing more than a table matching `Types.System`. It may declare
    dependencies on built-ins; because it is registered after `:Start()`, those dependencies
    must already be running, which AvatarContext is.
]]
local Greeter: Types.System = {
    Name = "GreeterSystem",
    Dependencies = { "AvatarContext" },

    Init = function(self: any, framework: Types.Unrest)
        self.Avatar = framework:Get("AvatarContext") :: Types.AvatarContext
        self.Seen = {} :: { [number]: boolean }
    end,

    Start = function(self: any)
        self.Avatar.CharacterAdded:Connect(function(player: Player)
            if self.Seen[player.UserId] then
                return
            end
            self.Seen[player.UserId] = true
            print(`[GreeterSystem] welcome, {player.Name}`)
        end)
    end,

    Destroy = function(self: any)
        table.clear(self.Seen)
    end,
}

plugins:Register(Greeter)

--------------------------------------------------------------------------------

local music = unrest:Get("MusicSystem") :: Types.MusicSystem
music:AddTrack({ Name = "Intermission", SoundId = "rbxassetid://1837879082", Volume = 0.25, Looped = true })

print(
    `[UnrestServer] Unrest {unrest.Version} ready -- systems: {table.concat(unrest.Core:List(), ", ")}`
        .. ` | tracks: {table.concat(music:List(), ", ")}`
        .. ` | plugins: {table.concat(plugins:List(), ", ")}`
)
