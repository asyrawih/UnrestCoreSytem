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
    Sliders.

    The framework drives the slider itself. A root carrying `UnrestGroup` and
    `UnrestWidget = "Slider"` gets a working one -- painted, dragged, and remembered across a
    rebuilt screen -- with no Luau at all. What is left in this file is the only part that is
    the game's: what a slider's value *means*.

    What Studio needs, per slider:

        Root   (Frame)        tag "Unrest", UnrestGroup = "Musik", UnrestWidget = "Slider"
          Label               UnrestRole = "SliderLabel"     -- optional
          Track               UnrestRole = "SliderTrack"
            Fill              UnrestRole = "SliderFill"      -- optional
            Knob (GuiButton)  UnrestRole = "SliderKnob"

    The tag goes on the root only. The rest arrive by cascade. Adding a tenth slider means
    duplicating a Frame in Studio and changing one attribute; there is nothing to add here.

    WHY THE CHANNEL NAME IS HERE AND NOT IN THE CONTROL. `Volume.<group>` is this game's
    vocabulary, and the framework must never spell one (CONVENTIONS). So the built-in Slider
    paints and reports a gesture, and this file is where a gesture becomes a channel.

    0..100 HERE, 0..1 THERE. The control works in fractions, because a fraction is what a
    position along a track is. Whole percent is a presentation choice, so the conversion
    happens at this boundary and `Actions` keeps the numbers it always had.

    TWO WAYS TO ACT ON THE VALUE, and they are not interchangeable.

      * Pass actions in, keyed by group. Each slider declares its own reaction, so there is no
        `if group == ...` chain and adding a slider never edits an existing handler.
      * Subscribe to the channel. A slider named here publishes `Volume.<group>` on every
        move, so anything else on screen can follow it with `UnrestChannel = "Volume.Musik"`
        and no code at all, and any script can `Bridge:Subscribe` to it.

    A GROUP WITH NO ENTRY still paints and still drags -- what is mounted is decided by
    `UnrestWidget` on the root, never by this table -- but it publishes nothing, because
    nothing here said what its value means. That is the one thing that changed when the
    control moved into the framework: nothing publishes on a group's behalf any more, and
    nothing is published at all until the player moves something.

    The split between change and commit matters. A volume slider wants every move, because the
    player is listening while they drag. Anything that costs something -- a request to the
    server, a reload -- wants only the value the player settled on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The built-in control's config type, so a misspelled field is a strict-mode error here.
local Slider = require(ReplicatedStorage.Unrest.Widgets.Controls.Slider)
local Types = require(ReplicatedStorage.Unrest.Types)
--- Generated from the place by `Tooling/Vocab` (see `studio/ExportVocab.luau`). A widget name
--- that is not in it is a widget no screen carries, and `--!strict` says so here rather than
--- at Play.
local Vocab = require(script.Parent.Parent.Vocab)

--- What one slider does with its own value. Both are optional.
export type Actions = {
    --- Fires on every move while dragging. `value` is 0..100.
    OnChange: ((value: number) -> ())?,
    --- Fires once when the pointer is released, with the value settled on.
    OnCommit: ((value: number) -> ())?,
}

--- Keyed by `UnrestGroup`. A group with no entry simply has no reaction.
export type Config = { [string]: Actions }

--- Whole percent, which is what this game's `Volume.*` channels carry.
local function percent(fraction: number): number
    return math.round(fraction * 100)
end

return function(unrest: Types.Unrest, config: Config?): ()
    local actions: Config = config or {}

    --- One control config per group named above, with the channel written into it.
    local wired: { [string]: Slider.SliderConfig } = {}
    for group, mine in actions do
        wired[group] = {
            OnChange = function(fraction: number)
                local value = percent(fraction)
                unrest.Bridge:Publish(`Volume.{group}`, value)

                local onChange = mine.OnChange
                if onChange ~= nil then
                    onChange(value)
                end
            end,

            OnCommit = function(fraction: number)
                local onCommit = mine.OnCommit
                if onCommit ~= nil then
                    onCommit(percent(fraction))
                end
            end,
        }
    end

    local sliders = unrest.Widgets:Use(Vocab.Widgets.Slider, wired)

    --[[
        A key that matches no slider does nothing at all, and a misspelled group name is
        exactly that. Silence is the failure mode this codebase keeps producing, so ask the
        handle which groups it actually ended up driving once the screen has had time to
        arrive, and say the rest out loud.
    ]]
    task.delay(5, function()
        local driving: { [string]: boolean } = {}
        for _, group in sliders:Groups() do
            driving[group] = true
        end

        for group in actions do
            if not driving[group] then
                warn(`[Slider] actions were given for "{group}" but no slider carries that UnrestGroup.`)
            end
        end
    end)
end
