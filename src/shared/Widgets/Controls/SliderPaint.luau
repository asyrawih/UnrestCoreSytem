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
    Unrest / Widgets / Controls / SliderPaint

    What a Slider and a Progress bar have in common. Both are a fill that grows along a track,
    a knob that may or may not be there, and a label that says how far along it is; the two
    controls differ only in whether the player is allowed to push the value around. So the
    painting is written once here and neither of them owns it.

    A PAINTER, NOT A PAINT FUNCTION. Optional roles arrive late -- a fill tagged after its
    track is a fill the widget was handed over without -- so `parts` is read on every paint
    rather than captured at mount. The one thing that has to be remembered between paints is
    whether the label has already been complained about, and that is the whole reason this
    hands back a closure: a label that cannot hold text would otherwise warn on every frame
    of a drag.

    ATTRIBUTES WARN. A role played by an instance that cannot do what the role means is a
    mistake made in Studio, by somebody not watching the output window. Say it once, name the
    instance, and keep painting everything else.

    NO CHANNEL, NO COMMAND. This paints and returns. Game names belong to the game.
]]

local Types = require(script.Parent.Parent.Parent.Types)

--[[
    The roles this touches. `SliderTrack` is not among them: the track is the rail a drag is
    measured against, and nothing paints it.
]]
local FILL = "SliderFill"
local KNOB = "SliderKnob"
local LABEL = "SliderLabel"

local SliderPaint = {}

--[[
    A caller's number, clamped to the 0..1 a fraction is.

    Raises rather than warns, and raises on NaN as loudly as on a string: this is reached from
    Luau -- `Set`, or an `Initial` in a config -- and code binding a control to a value it
    cannot hold is a bug, not data. `where` names the door it came in through, because the
    stack above this is the framework's own and says nothing useful.
]]
function SliderPaint.fraction(value: any, where: string): number
    if typeof(value) ~= "number" then
        error(`[Unrest.Widgets] {where} expects a number 0..1, got {typeof(value)}.`, 0)
    end

    local number = value :: number
    if number ~= number then
        error(`[Unrest.Widgets] {where} expects a number 0..1, got NaN.`, 0)
    end
    return math.clamp(number, 0, 1)
end

--- Builds the painter for one mounted group. Held for the life of the mount; see the header.
function SliderPaint.painter(group: string, parts: Types.WidgetParts): (fraction: number) -> ()
    local warned = false

    return function(fraction: number): ()
        local fill = parts[FILL]
        if fill ~= nil and fill:IsA("GuiObject") then
            fill.Size = UDim2.fromScale(fraction, 1)
        end

        --- Absent for a Progress bar, whose schema does not name one at all.
        local knob = parts[KNOB]
        if knob ~= nil and knob:IsA("GuiObject") then
            knob.Position = UDim2.fromScale(fraction, 0.5)
        end

        local label = parts[LABEL]
        if label == nil then
            return
        end

        --[[
            Whole percent, because a label is read by a person and 0.4 is not how a person
            says four tenths. The fraction stays the value; this is presentation, and the one
            place the two are allowed to differ.

            The cast is named `TextLabel` because Luau has no way to say "whichever of the
            three it turned out to be", and all three carry `Text`. The `IsA` is what makes
            it honest.
        ]]
        if label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox") then
            local writable = label :: TextLabel
            writable.Text = `{group}: {math.round(fraction * 100)}%`
        elseif not warned then
            warned = true
            warn(
                `[Unrest.Widgets] {label:GetFullName()} plays "{LABEL}" for group "{group}" but is a `
                    .. `{label.ClassName}, which has no Text to write. The rest of the widget still paints.`
            )
        end
    end
end

return SliderPaint
