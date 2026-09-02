--!strict
--[[
    Game -- ServerScriptService.Game

    The server bootstrap. Four lines, in the only order they work in:

        1. contracts   declared by requiring `ReplicatedStorage.Game`, in both realms
        2. systems     registered, then started, which is where handlers appear
        3. gateway     opened LAST, which is when the remotes appear

    Step 3 is last on purpose, and `Unrest:OpenGateway()` is written out here rather than
    hidden inside `:Start()` so that it stays last on purpose. Until it runs there is no
    remote for a client to send on, so the earliest request that can physically arrive already
    has a handler waiting for it.

    Everything under `Systems/` is server-authoritative and no client holds a reference to any
    of it. The only way in is the gateway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Game) -- 1. declares this game's contracts and presets
local Unrest = require(ReplicatedStorage.Unrest)

--- With ByteNet installed, the wire is chosen here, before `:Start()`:
--- `Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))`. Absent that, remotes.
Unrest:Register(require(script.Systems.Greeter)) -- 2. register systems
local unrest = Unrest:Start() -- 3. Init then Start; every handler is now registered
unrest:OpenGateway() -- 4. the remotes appear; only now can a client speak
