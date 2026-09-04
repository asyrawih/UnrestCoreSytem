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
    Toggle switches.

    The same shape as `Slider`, and for the same reason: the framework drives the switch
    itself, and this file is only where a press becomes a channel. A root carrying
    `UnrestGroup` and `UnrestWidget = "Toggle"` is a working switch with no Luau at all.

    What Studio needs, per switch:

        Root   (Frame)          tag "Unrest", UnrestGroup = "Musik", UnrestWidget = "Toggle"
          Button (GuiButton)    UnrestRole = "ToggleButton"    -- the whole track, clickable
            Knob (Frame)        UnrestRole = "ToggleKnob"      -- slides left and right
          Label  (TextLabel)    UnrestRole = "ToggleLabel"     -- optional

    The tag goes on the root only. The rest arrive by cascade.

    WHY THERE IS NO `OnCommit`. A slider has a drag, so "moving" and "settled on" are different
    moments and the split earns its keep. A switch has one press, and press is settled. Adding
    a second hook here would be symmetry for its own sake.

    `Initial` is the one thing a switch needs that a slider does not. A slider starts at zero
    because zero is a real position; a switch that assumed off would fight whatever the game
    already knows. Give it the truth and it paints that on the first frame -- once, on the
    first time that group is assembled. After that the state the player left it in is what a
    rebuilt screen comes back showing, and it comes back without publishing anything.

    A GROUP WITH NO ENTRY still works and still animates; it simply publishes nothing, because
    nothing here said what its state means.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The built-in control's config type, so a misspelled field is a strict-mode error here.
local ToggleControl = require(ReplicatedStorage.Unrest.Widgets.Controls.Toggle)
local Types = require(ReplicatedStorage.Unrest.Types)
--- Generated from the place by `Tooling/Vocab`; a misspelled widget name is a strict-mode
--- error here rather than a raise at Play.
local Vocab = require(script.Parent.Parent.Vocab)

--- What one switch does with its own state. Both are optional.
export type Actions = {
    --- The state to paint before anybody has touched it. Defaults to false.
    Initial: boolean?,
    --- Fires on every press, with the state the switch just moved to.
    OnChange: ((value: boolean) -> ())?,
}

--- Keyed by `UnrestGroup`. A group with no entry starts off and simply has no reaction.
export type Config = { [string]: Actions }

return function(unrest: Types.Unrest, config: Config?): ()
    local actions: Config = config or {}

    --- One control config per group named above, with the channel written into it.
    local wired: { [string]: ToggleControl.ToggleConfig } = {}
    for group, mine in actions do
        wired[group] = {
            Initial = mine.Initial,

            OnChange = function(value: boolean)
                unrest.Bridge:Publish(`Toggle.{group}`, value)

                local onChange = mine.OnChange
                if onChange ~= nil then
                    onChange(value)
                end
            end,
        }
    end

    local toggles = unrest.Widgets:Use(Vocab.Widgets.Toggle, wired)

    --[[
        A key that matches no switch does nothing at all, and a misspelled group name is
        exactly that. Ask the handle what it ended up driving once the screen has had time to
        arrive, and say the rest out loud.
    ]]
    task.delay(5, function()
        local driving: { [string]: boolean } = {}
        for _, group in toggles:Groups() do
            driving[group] = true
        end

        for group in actions do
            if not driving[group] then
                warn(`[Toggle] actions were given for "{group}" but no switch carries that UnrestGroup.`)
            end
        end
    end)
end
