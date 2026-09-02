--!strict
--[[
    Unrest / Constants

    Stringly-typed values that more than one layer needs. Keeping them here means a channel
    name is never spelled twice, and a typo is a nil index rather than a silent no-op.
]]

local Constants = {
    Version = "0.1.0",

    --- Default CollectionService tag stamped onto every framework-built UI element.
    Tag = "Unrest",

    --- Core -> UI. Retained state; subscribers immediately receive the last published value.
    Channels = table.freeze({
        NowPlaying = "Music.NowPlaying",
        MusicVolume = "Music.Volume",
        Character = "Avatar.Character",
        Dance = "Dance.Current",
        Plugins = "Plugin.Registered",
    }),

    --- UI -> Core. Fire-and-forget intents.
    Commands = table.freeze({
        MusicPlay = "Music.Play",
        MusicStop = "Music.Stop",
        DancePlay = "Dance.Play",
        DanceStop = "Dance.Stop",
        ChipActivated = "Chip.Activated",
        ChipRemoved = "Chip.Removed",
    }),
}

return table.freeze(Constants)
