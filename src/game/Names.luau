--!strict
--[[
    Game / Names

    The names of this game's channels and commands. Spelled here and nowhere else, so a
    typo is a nil index at the call site rather than a string that silently matches nothing.

    A name on its own grants nothing. `Contracts.luau` next door is what turns a name into
    something the framework will carry, and only a contract that says `AllowClient = true`
    makes one reachable from a client. Adding a line to this file is bookkeeping; adding a
    line to the contract table is a decision.
]]

local Names = {
    --- Core -> UI. Retained state; a subscriber immediately receives the last value.
    Channels = table.freeze({
        NowPlaying = "Music.NowPlaying",
        MusicVolume = "Music.Volume",
        Character = "Avatar.Character",
        Dance = "Dance.Current",
        Plugins = "Plugin.Registered",
    }),

    --- UI -> Core. Intents. Every one of these is declared in `Contracts.luau`, which is
    --- what decides whether a client may ask for it at all.
    Commands = table.freeze({
        MusicPlay = "Music.Play",
        MusicStop = "Music.Stop",
        MusicSetVolume = "Music.SetVolume",
        MusicForceStopAll = "Music.ForceStopAll",
        DancePlay = "Dance.Play",
        DanceStop = "Dance.Stop",
        PluginReload = "Plugin.Reload",
    }),
}

return table.freeze(Names)
