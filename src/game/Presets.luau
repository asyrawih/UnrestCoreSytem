--!strict
--[[
    Game / Presets

    A preset is a named bundle of wiring attributes. In Studio a designer writes one
    attribute:

        UnrestPreset = "MusicToggle"

    and the ElementManager expands it into the five that bundle stands for. The point is not
    brevity for its own sake -- it is that "what a music toggle is" gets decided once, in code,
    under review, instead of being retyped on every button and drifting.

    Precedence, most specific wins:

        the element's own attribute  >  its preset  >  the nearest ancestor's inheritable one

    So a preset is a default, never an override: set `UnrestPayload = "Dancefloor"` on one
    button using `MusicToggle` and that button plays Dancefloor while the rest play Lobby.

    Registering is a side effect of requiring, exactly as it is for the contracts next door.
    The framework ships `Presets.Register` and an empty table; which presets exist is a
    property of this game, so the list lives here.

    A preset naming a command the contracts do not declare is still refused at dispatch -- a
    preset is a shorthand, not a privilege.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Names = require(script.Parent.Names)
local Presets = require(ReplicatedStorage.Unrest.Presets)

local ATTRIBUTES = Constants.Attributes
local CHANNELS = Names.Channels
local COMMANDS = Names.Commands

--- A button that starts a track and shows what is playing.
Presets.Register("MusicToggle", {
    [ATTRIBUTES.Command] = COMMANDS.MusicPlay,
    [ATTRIBUTES.Payload] = "Lobby",
    [ATTRIBUTES.Channel] = CHANNELS.NowPlaying,
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Music: {value}",
})

--- A label that follows the current track and nothing else.
Presets.Register("NowPlayingLabel", {
    [ATTRIBUTES.Channel] = CHANNELS.NowPlaying,
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Now playing: {value}",
})

--- A button that stops the music.
Presets.Register("MusicStop", {
    [ATTRIBUTES.Command] = COMMANDS.MusicStop,
})

--[[
    A volume button. `UnrestPayload` is deliberately absent: the amount is the one thing that
    differs between two otherwise identical buttons, so it stays on the element.
]]
Presets.Register("VolumeButton", {
    [ATTRIBUTES.Command] = COMMANDS.MusicSetVolume,
})

--- A button that plays a dance. Set `UnrestPayload` to the dance name.
Presets.Register("DanceButton", {
    [ATTRIBUTES.Command] = COMMANDS.DancePlay,
    [ATTRIBUTES.Cooldown] = 0.5,
})

--- A button that stops the current dance.
Presets.Register("DanceStop", {
    [ATTRIBUTES.Command] = COMMANDS.DanceStop,
})

--- Registering is the point; read the registry back through `ReplicatedStorage.Unrest.Presets`
--- (`Presets.Get`, `Presets.List`) rather than through this module.
return table.freeze({})
