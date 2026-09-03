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
    One boolean, one property, several frames: the shared half of "this panel opens and shuts".

    Both panels in the server list do the same dance and animate DIFFERENT properties while
    doing it. The left one slides, because its ScreenGui carries no layout and `Position` is
    therefore its own; the right one grows out of zero width, because a `UIListLayout` on the
    container owns where it sits and tweening `Position` there would fight the layout every
    frame. Everything either of them does apart from that -- resting values read off the
    instance, one tween at a time, `Visible` opened early and closed late, the scopes that
    make an interrupted move silent -- is identical.

    It was identical in two files for about an hour, which is how this file came to exist.
    The repo has been bitten by exactly that before: two copies of the ancestor walk that
    agreed by coincidence until one of them expanded a preset the other never saw.

    WHAT A CALLER STILL OWNS. The channel, the roles, the queries, and when to call `Apply`.
    This file knows nothing about server lists; hand it a property name and a function that
    says where "hidden" is, and it will animate anything.

    THE RESTING VALUE IS READ, NEVER GIVEN. `Adopt` takes it off the instance before anything
    has moved it, because that value belongs to whoever laid the screen out. A caller that
    passed one in would be passing a copy of a number a designer owns, and dragging the panel
    a few pixels in Studio would leave the copy quietly wrong.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Unrest.Types)

--- What one reveal animates, and how.
export type Spec = {
    --- The property that moves. Must exist on every frame handed to `Adopt`.
    Property: string,
    --- Where a frame sits while hidden, given the resting value read off it.
    Hide: (resting: any) -> any,
    Open: TweenInfo,
    Close: TweenInfo,
}

--- One frame under a reveal's care.
type Panel = {
    --- Ends with the adoption.
    Scope: Types.Scope,
    --- Ends with the current move. A sub-scope of `Scope`, so it cannot be left behind.
    Animation: Types.Scope,
    --- The value the designer laid the frame out at.
    Resting: any,
    --- The state it is in or heading for -- not `frame.Visible`, which is true all the way
    --- through a close.
    Shown: boolean,
}

export type Reveal = {
    --- Takes a frame over and paints the given state instantly, without animating.
    Adopt: (self: Reveal, frame: GuiObject, open: boolean) -> (),
    --- Hands it back: the move is stopped and the frame put back where it was found.
    Release: (self: Reveal, frame: GuiObject) -> (),
    --- Animates every adopted frame to `open`. Frames already there are left alone.
    Apply: (self: Reveal, open: boolean) -> (),
    Destroy: (self: Reveal) -> (),
}

return function(Scope: Types.ScopeLibrary, spec: Spec): Reveal
    local panels: { [GuiObject]: Panel } = {}

    local reveal = {}
    local typed = (reveal :: any) :: Reveal

    local function write(frame: GuiObject, value: any): ()
        --- The property is a name rather than a field, so the write has to go through `any`.
        --- A name no frame has raises here, at the write, naming the property.
        (frame :: any)[spec.Property] = value
    end

    function reveal:Adopt(frame: GuiObject, open: boolean): ()
        local scope = Scope.scope()
        local resting = (frame :: any)[spec.Property]

        panels[frame] = {
            Scope = scope,
            Animation = Scope.add(scope, Scope.scope()),
            Resting = resting,
            Shown = open,
        }

        write(frame, if open then resting else spec.Hide(resting))
        frame.Visible = open
    end

    function reveal:Release(frame: GuiObject): ()
        local panel = panels[frame]
        if panel == nil then
            return
        end
        panels[frame] = nil

        --- Stops the move first, so nothing writes to the frame after the restore below.
        Scope.destroy(panel.Scope)

        --[[
            Then undo what this file did to it. A panel released mid-close would otherwise be
            left wherever the tween had got to -- half off the screen, or a few pixels wide,
            with no owner left to finish the job.
        ]]
        write(frame, panel.Resting)
        frame.Visible = panel.Shown
    end

    function reveal:Apply(open: boolean): ()
        for frame, panel in panels do
            --[[
                A value that says what the frame is already doing is not an event. Retained
                channels make this the common case rather than a rare one: subscribing replays
                the current value immediately, so without this every panel's first act on join
                is to tween from closed to closed -- and pay for a tween and a connection to
                do it.
            ]]
            if panel.Shown == open then
                continue
            end
            panel.Shown = open

            --- Whatever the last move left running. LIFO, so its connection is disconnected
            --- before its tween is destroyed and the interruption is silent.
            Scope.clean(panel.Animation)

            --[[
                Visible goes true at the START of opening and false at the END of closing. The
                asymmetry is the whole point: writing it false up front would take the panel
                off screen before the close tween had rendered a single frame, which is exactly
                the snap this file exists to avoid.
            ]]
            if open then
                frame.Visible = true
            end

            local goal: { [string]: any } = {}
            goal[spec.Property] = if open then panel.Resting else spec.Hide(panel.Resting)

            local tween = TweenService:Create(frame, if open then spec.Open else spec.Close, goal)

            --[[
                Tween first, connection second. Scythe disposes LIFO, so the connection is
                always disconnected BEFORE the tween it belongs to is destroyed -- which is
                what stops an interrupted close from reaching a handler that would flip
                `Visible` off in the middle of the opening tween.
            ]]
            Scope.addBulk(
                panel.Animation,
                tween,
                tween.Completed:Connect(function()
                    if not open then
                        frame.Visible = false
                    end

                    --- The move is over, so the tween and this connection stop meaning
                    --- anything. Cleaning a scope from inside it is supported: Scythe commits
                    --- the scope's state before it runs anything.
                    Scope.clean(panel.Animation)
                end)
            )

            tween:Play()
        end
    end

    function reveal:Destroy(): ()
        for frame in panels do
            typed:Release(frame)
        end
    end

    return typed
end
