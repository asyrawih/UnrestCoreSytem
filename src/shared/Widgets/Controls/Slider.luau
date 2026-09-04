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
    Unrest / Widgets / Controls / Slider

    The slider the framework drives itself. A root carrying `UnrestGroup` and
    `UnrestWidget = "Slider"` gets a working one with no Luau at all: the track is the rail,
    the knob is dragged along it, and the fill and the label are painted when they are there.

    WHAT IT DELIBERATELY DOES NOT DO. It never publishes and never dispatches. A built-in
    control that spelled `Volume.Musik` would put a game's vocabulary inside the framework,
    which is the one thing CONVENTIONS says the framework must never do. `OnChange` and
    `OnCommit` are how a gesture leaves here; what it *means* is written next to the code that
    owns it. That is also why `Mount` is handed the widget library and not the singleton --
    there is no bus in reach to publish on.

    MOUNTING IS NOT A GESTURE. The first paint calls nothing back. `Widgets` remembers the
    value a group was left at and hands it back through `Set`, which also paints in silence,
    so a screen rebuilt mid-session comes back where the player left it and announces nothing.
    `Initial` is read on the first mount of a group and never again, for the same reason.

    CHANGE AND COMMIT ARE DIFFERENT MOMENTS. A drag fires `OnChange` on every move, because a
    volume slider is being listened to while it is dragged, and `OnCommit` once, on the value
    the player settled on, because anything that costs something wants only that one.

    FRACTIONS, NOT PERCENTAGES. A position along a track is 0..1. Whole percent is a
    presentation choice and belongs to whoever is presenting.
]]

local Schemas = require(script.Parent.Parent.Schemas)
local Scope = require(script.Parent.Parent.Parent.Util.Scope)
local Signal = require(script.Parent.Parent.Parent.Util.Signal)
local SliderPaint = require(script.Parent.SliderPaint)
local Types = require(script.Parent.Parent.Parent.Types)

--- What one slider does with its own value. Every field is optional.
export type SliderConfig = {
    --- Where it sits before anybody has touched it, 0..1. First mount of a group only.
    Initial: number?,
    --- Every move of a drag.
    OnChange: ((fraction: number) -> ())?,
    --- Once, on release, at the value the player settled on.
    OnCommit: ((fraction: number) -> ())?,
}

--[[
    The schema this control is the driver for. Taken from `Schemas` rather than restated, so a
    game that replaces "Slider" with a schema of its own replaces what this control assembles
    too. It cannot be missing -- `Schemas` registers it itself -- and saying so out loud is
    cheaper than a nil that only shows up on somebody's screen.
]]
local SCHEMA = Schemas.Get("Slider")
if SCHEMA == nil then
    error('[Unrest.Widgets.Slider] no schema is registered under "Slider".', 0)
end

local Slider: Types.Control<SliderConfig> = {
    Name = "Slider",
    Schema = SCHEMA,

    Mount = function(
        widgets: Types.WidgetLibrary,
        group: string,
        parts: Types.WidgetParts,
        scope: Types.Scope,
        config: SliderConfig?
    ): Types.ControlHandle
        local settings: SliderConfig = config or {}
        local paint = SliderPaint.painter(group, parts)

        local changed: Types.Signal<any> = Signal.new(`Widgets.Slider[{group}]`)
        Scope.add(scope, changed)

        local fraction = if settings.Initial ~= nil
            then SliderPaint.fraction(settings.Initial, `Slider config for group "{group}" (Initial)`)
            else 0
        paint(fraction)

        --[[
            The track and the knob are the schema's required roles, so they are here. Their
            classes are not guaranteed: the runtime assembles by role and never refuses a part
            for what it is. A knob that is not a GuiObject cannot be pressed and a track that
            is not one cannot be measured, and both are mistakes made in Studio -- so the
            slider paints, says so once, and leaves the drag unbound rather than raising out
            of a handler the game never called.
        ]]
        local track = parts.SliderTrack
        local knob = parts.SliderKnob
        if track ~= nil and knob ~= nil and track:IsA("GuiObject") and knob:IsA("GuiObject") then
            widgets:Drag(scope, knob, track, function(moved: number)
                fraction = moved
                paint(fraction)
                changed:Fire(fraction)

                local onChange = settings.OnChange
                if onChange ~= nil then
                    onChange(fraction)
                end
            end, function(settled: number)
                fraction = settled

                local onCommit = settings.OnCommit
                if onCommit ~= nil then
                    onCommit(fraction)
                end
            end)
        else
            warn(
                `[Unrest.Widgets] group "{group}" is a Slider that cannot be dragged: `
                    .. `SliderTrack is a {if track ~= nil then track.ClassName else "nothing"} and SliderKnob is a `
                    .. `{if knob ~= nil then knob.ClassName else "nothing"}; both have to be GuiObjects.`
            )
        end

        return {
            Get = function(_self: Types.ControlHandle): any
                return fraction
            end,

            Set = function(_self: Types.ControlHandle, value: any): ()
                fraction = SliderPaint.fraction(value, `Slider:Set for group "{group}"`)
                paint(fraction)
            end,

            Changed = changed,
        }
    end,
}

return Slider
