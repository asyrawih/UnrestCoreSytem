--!strict
--[[
    Game -- ReplicatedStorage.Game

    The front door to this game's content, and the one thing both bootstraps require before
    they start anything.

        local Game = require(ReplicatedStorage.Game)
        unrest:Dispatch(Game.Commands.MusicPlay, "Lobby")

    REQUIRING THIS MODULE IS THE DECLARATION. The two requires below are not imports whose
    values are wanted -- they are the work. `Contracts` declares every command and channel
    into `Unrest.Net.Contracts`, and `Presets` registers every attribute bundle into
    `Unrest.Presets`. Handing back `Channels` and `Commands` afterwards is what makes that
    hard to get wrong: the only way to reach a name is through the module that already
    declared it, so "used a command nobody declared" is not a shape this codebase has.

    Roblox caches a required ModuleScript per realm, so the declarations run exactly once no
    matter how many files require this one. The server and the client keep separate caches
    and therefore each run them once -- which is not a duplicate, it is the point: both
    realms read their own copy of the registry, and both have to be told.

    Neither `:Declare` nor `Presets.Register` is idempotent -- declaring a name twice is
    refused outright -- and this module is what makes sure nobody ever tries.

    THE DEPENDENCY RUNS ONE WAY. Everything here requires the framework; nothing under
    `src/shared` may require anything here. The framework does not know this game exists.
]]

local Names = require(script.Names)

--- Declares this game's commands and channels. Required for the side effect.
require(script.Contracts)
--- Registers this game's preset attribute bundles. Required for the side effect.
require(script.Presets)

local Game = {
    --- Core -> UI. Retained state.
    Channels = Names.Channels,
    --- UI -> Core. Intents, each one declared and each one gated by its contract.
    Commands = Names.Commands,
}

return table.freeze(Game)
