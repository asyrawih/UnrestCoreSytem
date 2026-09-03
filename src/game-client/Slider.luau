--!strict
--[[
    Sliders.

    A slider is four tagged parts that only mean something together, and `UnrestGroup` on their
    shared root is what says which slider they belong to. Group is inheritable, so the root
    carries it once and the parts beneath inherit it.

    Adding a tenth slider means duplicating a Frame in Studio and changing one attribute. There
    is no new role, no new query, and nothing to add here.

    What Studio needs, per slider:

        Root   (Frame)        tag "Unrest", UnrestGroup = "Music"
          Label               UnrestRole = "SliderLabel"
          Track               UnrestRole = "SliderTrack"
            Fill              UnrestRole = "SliderFill"
            Knob (GuiButton)  UnrestRole = "SliderKnob"

    The tag goes on the root only. The rest arrive by cascade.

    TWO WAYS TO ACT ON THE VALUE, and they are not interchangeable.

      * Pass actions in, keyed by group. Each slider declares its own reaction, so there is no
        `if group == ...` chain and adding a slider never edits an existing handler.
      * Subscribe to the channel. Every slider publishes `Volume.<group>` regardless, so
        anything else on screen can follow it with `UnrestChannel = "Volume.Music"` and no code
        at all, and any script can `Bridge:Subscribe` to it.

    A slider with no entry in the table still paints and still publishes. Actions are for a
    reaction the caller owns; they are not what makes a slider work.

    The split between change and commit matters. A volume slider wants every move, because the
    player is listening while they drag. Anything that costs something -- a request to the
    server, a reload -- wants only the value the player settled on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)
local Widget = require(script.Parent.Widget)

local ROLES = { "SliderTrack", "SliderFill", "SliderKnob", "SliderLabel" }

--- What one slider does with its own value. Both are optional.
export type Actions = {
    --- Fires on every move while dragging. `value` is 0..100.
    OnChange: ((value: number) -> ())?,
    --- Fires once when the pointer is released, with the value settled on.
    OnCommit: ((value: number) -> ())?,
}

--- Keyed by `UnrestGroup`. A group with no entry simply has no reaction.
export type Config = { [string]: Actions }

return function(unrest: Types.Unrest, config: Config?): ()
    local actions: Config = config or {}
    local seen: { [string]: boolean } = {}

    --[[
        A key that matches no slider does nothing at all, and a misspelled group name is
        exactly that. Silence is the failure mode this codebase keeps producing, so say it out
        loud once the screen has had time to arrive.
    ]]
    task.delay(5, function()
        for group in actions do
            print(`seen group {group}`)
            if not seen[group] then
                warn(`[Slider] actions were given for "{group}" but no slider carries that UnrestGroup.`)
            end
        end
    end)

    Widget.each(unrest, ROLES, function(group: string, parts: Widget.Parts)
        seen[group] = true

        print(`seen group {seen[group]}`)

        local mine: Actions = actions[group] or {}
        local track = parts.SliderTrack :: Frame
        local fill = parts.SliderFill :: Frame
        local knob = parts.SliderKnob :: GuiObject
        local label = parts.SliderLabel :: TextLabel

        --- Paints, publishes, and returns the whole-number value the caller sees.
        local function paint(fraction: number): number
            local value = math.round(fraction * 100)

            fill.Size = UDim2.fromScale(fraction, 1)
            knob.Position = UDim2.fromScale(fraction, 0.5)
            label.Text = `{group}: {value}%`
            unrest.Bridge:Publish(`Volume.{group}`, value)

            return value
        end

        paint(0)

        local function onCommit(fraction: number): ()
            if mine.OnCommit ~= nil then
                mine.OnCommit(math.round(fraction * 100))
            end
        end

        Widget.drag(unrest, knob, track, function(fraction: number)
            local value = paint(fraction)
            if mine.OnChange ~= nil then
                mine.OnChange(value)
            end
        end, onCommit)
    end)
end
