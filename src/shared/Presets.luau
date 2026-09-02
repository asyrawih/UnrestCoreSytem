--!strict
--[[
    Unrest / Presets

    A preset is a named bundle of wiring attributes. In Studio a designer writes one
    attribute:

        UnrestPreset = "MusicToggle"

    and the ElementManager expands it into the five that bundle stands for. The point is
    not brevity for its own sake -- it is that "what a music toggle is" gets decided once,
    in code, under review, instead of being retyped on every button and drifting.

    Precedence, most specific wins:

        the element's own attribute  >  its preset  >  the nearest ancestor's inheritable one

    So a preset is a default, never an override: set `UnrestPayload = "Dancefloor"` on one
    button using `MusicToggle` and that button plays Dancefloor while the rest play Lobby.

    Adding a preset here changes no framework code. A preset naming a command the contracts
    do not declare is still refused at dispatch -- a preset is a shorthand, not a privilege.
]]

local Constants = require(script.Parent.Constants)

local ATTRIBUTES = Constants.Attributes
local CHANNELS = Constants.Channels
local COMMANDS = Constants.Commands

export type Preset = { [string]: any }

local PRESETS: { [string]: Preset } = {
    --- A button that starts a track and shows what is playing.
    MusicToggle = {
        [ATTRIBUTES.Command] = COMMANDS.MusicPlay,
        [ATTRIBUTES.Payload] = "Lobby",
        [ATTRIBUTES.Channel] = CHANNELS.NowPlaying,
        [ATTRIBUTES.Bind] = "Text",
        [ATTRIBUTES.Format] = "Music: {value}",
    },

    --- A label that follows the current track and nothing else.
    NowPlayingLabel = {
        [ATTRIBUTES.Channel] = CHANNELS.NowPlaying,
        [ATTRIBUTES.Bind] = "Text",
        [ATTRIBUTES.Format] = "Now playing: {value}",
    },

    --- A button that stops the music.
    MusicStop = {
        [ATTRIBUTES.Command] = COMMANDS.MusicStop,
    },

    --[[
        A volume button. `UnrestPayload` is deliberately absent: the amount is the one thing
        that differs between two otherwise identical buttons, so it stays on the element.
    ]]
    VolumeButton = {
        [ATTRIBUTES.Command] = COMMANDS.MusicSetVolume,
    },

    --- A button that plays a dance. Set `UnrestPayload` to the dance name.
    DanceButton = {
        [ATTRIBUTES.Command] = COMMANDS.DancePlay,
        [ATTRIBUTES.Cooldown] = 0.5,
    },

    --- A button that stops the current dance.
    DanceStop = {
        [ATTRIBUTES.Command] = COMMANDS.DanceStop,
    },
}

local Presets = {}

--- The attribute bundle named `name`, or nil when no such preset is declared.
function Presets.Get(name: string): Preset?
    return PRESETS[name]
end

--- Declared preset names, sorted, for error messages and tooling.
function Presets.List(): { string }
    local names: { string } = {}
    for name in PRESETS do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--[[
    Registers a preset at runtime, so a game can add its own without editing this file.
    Replacing a declared name is allowed and intentional: a game that wants `MusicToggle` to
    mean something else should be able to say so in one place.
]]
function Presets.Register(name: string, preset: Preset): Preset
    if typeof(name) ~= "string" or name == "" then
        error(`[Unrest.Presets] :Register expects a non-empty name, got {typeof(name)}.`, 0)
    end
    if typeof(preset) ~= "table" then
        error(`[Unrest.Presets] :Register("{name}", ...) expects a table of attributes.`, 0)
    end

    for key in preset do
        if typeof(key) ~= "string" or key:sub(1, 6) ~= "Unrest" then
            error(
                `[Unrest.Presets] preset "{name}" has key {tostring(key)}, which is not an `
                    .. `Unrest attribute name. Use the names in Constants.Attributes.`,
                0
            )
        end
    end

    PRESETS[name] = preset
    return preset
end

return Presets
