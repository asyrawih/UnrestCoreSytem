--!strict
--[[
    UnrestServer -- ServerScriptService.UnrestServer

    The server bootstrap, and the whole flow in one file, in the order it has to happen:

        1. contracts        already declared, in ReplicatedStorage, read by both realms
        2. systems          registered, then started, in dependency order
        3. handlers         registered by each system's Init, through the Bridge
        4. gateway          started LAST, which is when the remotes appear

    Step 4 is last on purpose. `Net.Create()` is what makes the remotes exist in
    ReplicatedStorage, and the client cannot send anything before they do. Starting the
    gateway at the end means the earliest request a client is physically able to make already
    has a registered handler waiting for it -- there is no window in which the door is open and
    the room behind it is empty.

    Everything in `Systems/` is server-authoritative and no client holds a reference to any of
    it. The only path in is the gateway.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Types = require(ReplicatedStorage.Unrest.Types)
local Unrest = require(ReplicatedStorage.Unrest)

local NetServer = require(script.Net.Server)

local AvatarContext = require(script.Systems.AvatarContext)
local DanceSystem = require(script.Systems.DanceSystem)
local MusicSystem = require(script.Systems.MusicSystem)
local PluginExtended = require(script.Systems.PluginExtended)

--------------------------------------------------------------------------------
-- 1 + 2. Systems. Registration order is irrelevant -- Core sorts by `Dependencies`.
--------------------------------------------------------------------------------

Unrest:Register(MusicSystem)
Unrest:Register(AvatarContext)
Unrest:Register(DanceSystem)
Unrest:Register(PluginExtended)

--- `Start` runs every `Init` (which is where each system calls `Bridge:Handle`) and then every
--- `Start`. By the time this returns, every command in the contract table that this server
--- owns has a handler.
local unrest = Unrest:Start()

--------------------------------------------------------------------------------
-- Plugin Extended: a third-party system, registered after startup.
--------------------------------------------------------------------------------

local plugins = unrest:Get("PluginExtended") :: Types.PluginExtended

--[[
    A plugin is nothing more than a table matching `Types.System`. It may declare dependencies
    on built-ins; because it is registered after `:Start()`, those dependencies must already be
    running, which AvatarContext is.
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
-- Server-side content. None of this is reachable from a client.
--------------------------------------------------------------------------------

local music = unrest:Get("MusicSystem") :: Types.MusicSystem
music:AddTrack({ Name = "Intermission", SoundId = "rbxassetid://1837879082", Volume = 0.25, Looped = true })

--------------------------------------------------------------------------------
-- 4. The gateway. Everything a client can reach passes through this object.
--------------------------------------------------------------------------------

local gateway = NetServer.new(unrest.Bridge)

--[[
    Two observation hooks, and neither of them acts. `Rejected` is where telemetry belongs;
    `AbuseDetected` is where moderation belongs. The framework reports and the game decides --
    an automatic kick on a rejection count bans the player with the bad connection and the one
    whose button double-fired.
]]
gateway.Rejected:Connect(function(rejection: Types.Rejection)
    local who = if rejection.Player ~= nil then rejection.Player.Name else "<server>"
    print(`[UnrestServer] rejected {rejection.Command} from {who}: {rejection.Reason}`)
end)

gateway.AbuseDetected:Connect(function(player: Player, count: number)
    warn(`[UnrestServer] {player.Name} has been refused {count} times. Reporting, not kicking.`)
end)

gateway:Start()

--------------------------------------------------------------------------------
-- A worked example of the boundary, run once at boot.
--------------------------------------------------------------------------------

--[[
    Both of these are ordinary dispatches from server code, and both run locally because their
    contracts put them on the server. The second one is unreachable from any client; nothing
    about this call site says so, and nothing about it has to. The difference lives in
    `Net/Contracts.luau`, in the presence or absence of one `AllowClient = true` line.
]]
unrest.Bridge:Dispatch(Constants.Commands.MusicForceStopAll, nil)
unrest.Bridge:Dispatch(Constants.Commands.MusicPlay, "Lobby")

local clientCallable: { string } = {}
local serverOnly: { string } = {}
for name in unrest.Bridge.Contracts.Commands do
    table.insert(if unrest.Bridge.Contracts:IsClientCallable(name) then clientCallable else serverOnly, name)
end
table.sort(clientCallable)
table.sort(serverOnly)

print(
    `[UnrestServer] Unrest {unrest.Version} ready -- systems: {table.concat(unrest.Core:List(), ", ")}`
        .. ` | tracks: {table.concat(music:List(), ", ")}`
        .. ` | plugins: {table.concat(plugins:List(), ", ")}`
)
print(
    `[UnrestServer] gateway open -- client-callable: {table.concat(clientCallable, ", ")}`
        .. ` | server-only: {table.concat(serverOnly, ", ")}`
        .. ` | players: {#Players:GetPlayers()}`
)
