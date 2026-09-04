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
    Unrest / Widgets / Controls / Progress

    A slider the player cannot touch: the same fill, the same optional label, no knob and no
    drag. It is the schema's difference made real -- `Progress` requires a track and a fill
    and never names a knob -- rather than a second control that happens to look alike, which
    is why the painting comes from `SliderPaint` and this file is the thin part.

    THE VALUE ONLY EVER ARRIVES FROM OUTSIDE. Nothing here is a gesture, so `Changed` exists
    and never fires, there is no `Committed` for a gesture to settle into, and the whole of the
    API is `handle:Set(fraction)`. `Initial` is what it shows until somebody says otherwise,
    read on the first mount of a group and never again; after that the value it was left at is
    what a rebuilt screen comes back showing.

    Which makes an `UnrestChannel` on its root read one way only: a progress bar follows the
    channel and can never publish to it, because it has no gesture to publish from.
]]

local Schemas = require(script.Parent.Parent.Schemas)
local Scope = require(script.Parent.Parent.Parent.Util.Scope)
local Signal = require(script.Parent.Parent.Parent.Util.Signal)
local SliderPaint = require(script.Parent.SliderPaint)
local Types = require(script.Parent.Parent.Parent.Types)

--- What one progress bar shows. There is nothing to react to, so there is nothing but this.
export type ProgressConfig = {
    --- What it shows before anybody sets it, 0..1. First mount of a group only.
    Initial: number?,
}

--- Taken from `Schemas` rather than restated; see the note in `Controls/Slider.luau`.
local SCHEMA = Schemas.Get("Progress")
if SCHEMA == nil then
    error('[Unrest.Widgets.Progress] no schema is registered under "Progress".', 0)
end

local Progress: Types.Control<ProgressConfig> = {
    Name = "Progress",
    Schema = SCHEMA,

    Mount = function(
        _widgets: Types.WidgetLibrary,
        group: string,
        parts: Types.WidgetParts,
        scope: Types.Scope,
        config: ProgressConfig?
    ): Types.ControlHandle
        local settings: ProgressConfig = config or {}
        local paint = SliderPaint.painter(group, parts)

        --- Minted so the handle's shape is the same as every other control's. A caller may
        --- connect to it; it will simply never fire, because nobody can push a progress bar.
        local changed: Types.Signal<any> = Signal.new(`Widgets.Progress[{group}]`)
        Scope.add(scope, changed)

        local fraction = if settings.Initial ~= nil
            then SliderPaint.fraction(settings.Initial, `Progress config for group "{group}" (Initial)`)
            else 0
        paint(fraction)

        return {
            Get = function(_self: Types.ControlHandle): any
                return fraction
            end,

            Set = function(_self: Types.ControlHandle, value: any): ()
                fraction = SliderPaint.fraction(value, `Progress:Set for group "{group}"`)
                paint(fraction)
            end,

            Changed = changed,
        }
    end,
}

return Progress
