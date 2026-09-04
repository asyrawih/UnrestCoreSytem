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
    Unrest / Widgets / Controls / Toggle

    The switch the framework drives itself. A root carrying `UnrestGroup` and
    `UnrestWidget = "Toggle"` gets a working one: the button is the whole track and is what is
    pressed, the knob slides between its two ends, and the label says which end it is at.

    WHY THERE IS NO `OnCommit`. A slider has a drag, so "moving" and "settled on" are
    different moments and the split earns its keep. A switch has one press, and a press is
    already settled. A second hook here would be symmetry for its own sake. The handle does
    carry `Committed`, fired on the same press as `Changed` and straight after it, because the
    framework's routing asks every control the same question -- "is this gesture over yet" --
    and a switch's answer is always yes.

    ONLY A PRESS ANIMATES. The slide is what a press looks like, so it belongs to a press and
    to nothing else. A switch that slid into place on join -- or when the game called `Set`,
    or when a rebuilt screen came back at the value it had -- would look like something the
    player did, which is exactly the thing it must not look like.

    IT NEVER PUBLISHES. See `Controls/Slider.luau`: `OnChange` is how a press leaves here, and
    what it means is written next to the code that owns it.

    THE TWO RESTING PLACES ARE MEASURED, NOT ASSUMED. `UDim2.fromScale(0, 0.5)` and
    `(1, 0.5)` put the knob's centre on the track's edge, so with the usual centred anchor
    half of it hangs outside at both ends. Offsetting by half the knob's own width plus the
    padding keeps it flush inside, and doing that in offset rather than scale keeps it correct
    at any track width. `AbsoluteSize` is `0, 0` until the first layout pass, so the
    measurement is taken on every paint and a resize repaints.
]]

local TweenService = game:GetService("TweenService")

local Schemas = require(script.Parent.Parent.Schemas)
local Scope = require(script.Parent.Parent.Parent.Util.Scope)
local Signal = require(script.Parent.Parent.Parent.Util.Signal)
local Types = require(script.Parent.Parent.Parent.Types)

--- What one switch does with its own state. Both fields are optional.
export type ToggleConfig = {
    --- The state to paint before anybody has touched it. First mount of a group only.
    Initial: boolean?,
    --- Every press, with the state the switch just moved to.
    OnChange: ((value: boolean) -> ())?,
}

local OFF_COLOUR = Color3.fromRGB(60, 60, 68)
local ON_COLOUR = Color3.fromRGB(124, 58, 237)

--- Gap between the knob and the end of the track it slides in.
local PADDING = 2

local SLIDE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--- Taken from `Schemas` rather than restated; see the note in `Controls/Slider.luau`.
local SCHEMA = Schemas.Get("Toggle")
if SCHEMA == nil then
    error('[Unrest.Widgets.Toggle] no schema is registered under "Toggle".', 0)
end

local Toggle: Types.Control<ToggleConfig> = {
    Name = "Toggle",
    Schema = SCHEMA,

    Mount = function(
        _widgets: Types.WidgetLibrary,
        group: string,
        parts: Types.WidgetParts,
        scope: Types.Scope,
        config: ToggleConfig?
    ): Types.ControlHandle
        local settings: ToggleConfig = config or {}

        local changed: Types.Signal<any> = Signal.new(`Widgets.Toggle[{group}]`)
        Scope.add(scope, changed)
        --[[
            A press is already settled, so this fires on the same press and immediately after
            `Changed` -- the two moments are the same moment here. It exists so the framework's
            routing has one rule for every control rather than one for the ones with a drag and
            another for the ones without; see `Widgets`. There is still no `OnCommit` config,
            because a caller has nothing to tell apart.
        ]]
        local committed: Types.Signal<any> = Signal.new(`Widgets.Toggle[{group}].Committed`)
        Scope.add(scope, committed)

        local state = settings.Initial == true

        --[[
            The button and the knob are required roles, so they are here; their *classes* are
            not guaranteed, because the runtime assembles by role and never refuses a part for
            what it is. Narrowed once, and the switch stays inert when either is wrong: a
            press needs a GuiButton and a slide needs something with a Position. That is a
            mistake made in Studio, so it warns and keeps the screen up rather than raising
            out of a handler the game never called.
        ]]
        local pressed = parts.ToggleButton
        local sliding = parts.ToggleKnob
        local track: GuiButton? = if pressed ~= nil and pressed:IsA("GuiButton") then pressed else nil
        local slider: GuiObject? = if sliding ~= nil and sliding:IsA("GuiObject") then sliding else nil

        local function paint(animate: boolean): ()
            if track == nil or slider == nil then
                return
            end

            local half = slider.AbsoluteSize.X / 2
            local inset = half + PADDING
            local position = if state then UDim2.new(1, -inset, 0.5, 0) else UDim2.new(0, inset, 0.5, 0)
            local colour = if state then ON_COLOUR else OFF_COLOUR

            if animate then
                TweenService:Create(slider, SLIDE, { Position = position }):Play()
                TweenService:Create(track, SLIDE, { BackgroundColor3 = colour }):Play()
            else
                slider.Position = position
                track.BackgroundColor3 = colour
            end

            --- Read late rather than captured, because the label is optional and may have
            --- arrived after this widget was handed over.
            local label = parts.ToggleLabel
            if label == nil then
                return
            end

            --- One cast for either text class; see the same note in `SliderPaint`.
            if label:IsA("TextLabel") or label:IsA("TextButton") then
                local writable = label :: TextLabel
                writable.Text = `{group}: {if state then "on" else "off"}`
            end
        end

        paint(false)

        if track == nil or slider == nil then
            warn(
                `[Unrest.Widgets] group "{group}" is a Toggle that cannot be pressed: ToggleButton is a `
                    .. `{if pressed ~= nil then pressed.ClassName else "nothing"} and ToggleKnob is a `
                    .. `{if sliding ~= nil then sliding.ClassName else "nothing"}; they have to be a GuiButton `
                    .. `and a GuiObject.`
            )
        else
            --[[
                Both connections go on the scope the framework handed over, so untagging the
                switch or rebuilding the screen takes them with it.

                `track.Activated` rather than a query on the `ToggleButton` role. A query would
                match every switch on screen and need a `pressed ~= button` guard to throw away
                the other switches' presses -- one query and one set of watchers per switch, to
                learn something we are already holding. `Activated` is the same event the
                framework's own `Active` handler binds to on a GuiButton, minus the search.
            ]]
            Scope.addBulk(
                scope,
                --- A resize moves both ends, so the knob has to be put back where it belongs.
                slider:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                    paint(false)
                end),
                track.Activated:Connect(function()
                    state = not state
                    paint(true)
                    changed:Fire(state)
                    committed:Fire(state)

                    local onChange = settings.OnChange
                    if onChange ~= nil then
                        onChange(state)
                    end
                end)
            )
        end

        return {
            Get = function(_self: Types.ControlHandle): any
                return state
            end,

            Set = function(_self: Types.ControlHandle, value: any): ()
                if typeof(value) ~= "boolean" then
                    error(`[Unrest.Widgets] Toggle:Set for group "{group}" expects a boolean, got {typeof(value)}.`, 0)
                end
                state = value
                paint(false)
            end,

            Changed = changed,
            Committed = committed,
        }
    end,
}

return Toggle
