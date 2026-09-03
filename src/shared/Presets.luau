--!strict
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

--[[
    Unrest / Presets

    A preset is a named bundle of wiring attributes. In Studio a designer writes one
    attribute:

        UnrestPreset = "PrimaryAction"

    and the ElementManager expands it into the several that bundle stands for. The point is
    not brevity for its own sake -- it is that "what a primary action button is" gets decided
    once, in code, under review, instead of being retyped on every button and drifting.

    Precedence, most specific wins:

        the element's own attribute  >  its preset  >  the nearest ancestor's inheritable one

    So a preset is a default, never an override: set `UnrestPayload` on one button using a
    preset and that button carries its own payload while the rest keep the preset's.

    THE FRAMEWORK SHIPS NO PRESETS. A preset names a command or a channel, and command and
    channel names belong to the game, not here. The table below is empty on purpose; a game
    fills it with `Presets.Register` at startup and the framework never needs to know what
    went in.

    Registering a preset changes no framework code. A preset naming a command nothing
    handles simply dispatches into an empty room -- a preset is a shorthand for a bundle of
    attributes, and nothing more.
]]

export type Preset = { [string]: any }

--- Empty by design: see the header. Every entry here arrives through `Presets.Register`.
local PRESETS: { [string]: Preset } = {}

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
    Registers a preset. This is how every preset gets here: the framework declares none, so
    a game names its own bundles at startup without editing this file.

    Replacing a name already registered is allowed and intentional -- a game that wants one
    of its presets to mean something else should be able to say so in one place, rather than
    finding every element that names it.
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
