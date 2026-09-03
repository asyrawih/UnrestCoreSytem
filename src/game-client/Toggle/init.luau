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

    The same shape as `Slider`: a widget is several tagged parts that only mean something
    together, `UnrestGroup` on their shared root says which switch they belong to, and actions
    are keyed by that group so adding a switch never edits an existing handler.

    What Studio needs, per switch:

        Root   (Frame)          tag "Unrest", UnrestGroup = "Music"
          Button (GuiButton)    UnrestRole = "ToggleButton"    -- the whole track, clickable
            Knob (Frame)        UnrestRole = "ToggleKnob"      -- slides left and right
          Label  (TextLabel)    UnrestRole = "ToggleLabel"     -- optional

    The tag goes on the root only. The rest arrive by cascade.

    WHY THERE IS NO `OnCommit`. A slider has a drag, so "moving" and "settled on" are different
    moments and the split earns its keep. A switch has one press, and press is settled. Adding
    a second hook here would be symmetry for its own sake.

    `Initial` is the one thing a switch needs that a slider does not. A slider starts at zero
    because zero is a real position; a switch that assumes off would fight whatever the game
    already knows. Give it the truth and it paints that on the first frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Unrest.Types)

local REQUIRED = { "ToggleButton", "ToggleKnob" }
local OPTIONAL = { "ToggleLabel" }

local OFF_COLOUR = Color3.fromRGB(60, 60, 68)
local ON_COLOUR = Color3.fromRGB(124, 58, 237)

--- Gap between the knob and the end of the track it slides in.
local PADDING = 2

local SLIDE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
    local seen: { [string]: boolean } = {}

    --[[
        A key that matches no switch does nothing at all, and a misspelled group name is
        exactly that. Say it out loud once the screen has had time to arrive.
    ]]
    task.delay(5, function()
        for group in actions do
            if not seen[group] then
                warn(`[Toggle] actions were given for "{group}" but no switch carries that UnrestGroup.`)
            end
        end
    end)

    local function onReady(group: string, parts: Types.WidgetParts, scope: Types.Scope): ()
        seen[group] = true

        local mine: Actions = actions[group] or {}
        local button = parts.ToggleButton :: GuiButton
        local knob = parts.ToggleKnob :: GuiObject

        local state = mine.Initial == true

        --[[
            The two resting positions, measured rather than assumed.

            `UDim2.fromScale(0, 0.5)` and `(1, 0.5)` put the knob's centre on the track's edge,
            so with the usual centred anchor half of it hangs outside at both ends. Offsetting
            by half the knob's own width, plus the padding, keeps it flush inside -- and doing
            it in offset rather than scale means it stays correct at any track width.

            `AbsoluteSize` is `0, 0` until the first layout pass, and a widget adopted before
            its screen has been laid out would measure zero and stack both ends on top of each
            other. So the measurement is taken every paint, and a size change repaints.
        ]]
        local function restingPlaces(): (UDim2, UDim2)
            local half = knob.AbsoluteSize.X / 2
            local inset = half + PADDING
            return UDim2.new(0, inset, 0.5, 0), UDim2.new(1, -inset, 0.5, 0)
        end

        --- `animate` is false for the opening paint: a switch that slides into place on join
        --- looks like something the player did.
        local function paint(animate: boolean): ()
            local off, on = restingPlaces()
            local position = if state then on else off
            local colour = if state then ON_COLOUR else OFF_COLOUR

            if animate then
                TweenService:Create(knob, SLIDE, { Position = position }):Play()
                TweenService:Create(button, SLIDE, { BackgroundColor3 = colour }):Play()
            else
                knob.Position = position
                button.BackgroundColor3 = colour
            end

            --- Read late rather than captured, because the label is optional and may have
            --- arrived after this widget was handed over.
            local label = parts.ToggleLabel :: TextLabel?
            if label ~= nil then
                label.Text = `{group}: {if state then "on" else "off"}`
            end

            unrest.Bridge:Publish(`Toggle.{group}`, state)
        end

        paint(false)

        --[[
            Both connections go on the scope the framework handed over, so untagging the switch
            or rebuilding the screen takes them with it.

            `button.Activated` rather than a query on the `ToggleButton` role. A query would
            match every switch on screen and need a `pressed ~= button` guard to throw away the
            other switches' presses -- one query and one set of watchers per switch, to learn
            something we are already holding. `Activated` is the same event the framework's own
            `Active` handler binds to on a GuiButton, minus the search for the button.
        ]]
        unrest.Scope.addBulk(
            scope,
            --- A resize moves both ends, so the knob has to be put back where it now belongs.
            knob:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                paint(false)
            end),
            button.Activated:Connect(function()
                state = not state
                paint(true)

                if mine.OnChange ~= nil then
                    mine.OnChange(state)
                end
            end)
        )
    end

    unrest.Widgets:Each({
        Required = REQUIRED,
        Optional = OPTIONAL,
        OnReady = onReady,
    })
end
