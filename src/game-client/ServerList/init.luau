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
    The server list panel: whether it is open, and nothing else.

    One boolean on one channel is the whole state. The button publishes it, the panel obeys
    it, and neither knows the other exists:

        E_ServerListButton  --publish-->  "ServerList.Open"  --subscribe-->  ServerListContainer

    The rows inside it are `Directory`, and the panel that opens beside it is `Info`. Both are
    required here and both hand back a cleanup, so the whole feature comes down in one call
    and in the right order.

    WHY THE PANEL IS NOT WIRED WITH `UnrestChannel` + `UnrestBind`. It was, and that is the
    zero-code way to do this -- the framework writes `Visible` the moment a value lands. But
    `Visible` is a boolean, so it snaps, and a snap is not an animation: the panel would be
    gone before the first frame of the close tween rendered. Wanting a tween means wanting
    something between the two states, and that is what a bind cannot express. So the panel
    keeps `UnrestRole` and nothing else, and this file listens to the same channel the bind
    used to.

    What Studio needs, on `StarterGui.InGame.ServerListContainer`:

        Tag        "Unrest"
        UnrestRole "ServerListPanel"

    and specifically NOT `UnrestChannel` / `UnrestBind` -- leaving either one on fights every
    tween this file starts, and the fight is silent.

    THE ROLE IS `ServerListPanel` AND NOT `ServerListFrame`, WHICH IS NOT COSMETIC. `Role`
    resolves to `UnrestRole` OR, when that is unset, the instance's own name -- so a role
    string that is also somebody's name selects both. This container holds a child Frame that
    was called `ServerListFrame`, and the old role matched the container a designer opted in
    AND the namesake one level down inside it. Sliding a panel's own child out from under it
    looks exactly like the panel tearing in half. Any role here has to be a word nothing else
    in the screen answers to.

    WHY POSITION AND NOT TRANSPARENCY. The container's own `BackgroundTransparency` is already
    1: what a player sees is its children, and fading a Frame does not fade its subtree. A
    fade would mean converting it to a `CanvasGroup` and tweening `GroupTransparency`, which
    is a fine change but a change to the UI, not to this file. Sliding needs neither -- its
    ScreenGui carries no layout, so nothing else is writing `Position` and it is ours to move.

    Its `UIScale` is deliberately left alone. It is tagged `Managed-Frame`, which is another
    system's handle on it, and two owners animating one property is a bug that only shows up
    when both happen to run at once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Channels = require(script.Channels)
local Directory = require(script.Directory)
local Info = require(script.Info)
local RevealFactory = require(script.Reveal)
local Types = require(ReplicatedStorage.Unrest.Types)
local Vocab = require(script.Parent.Vocab)

--- Out is quicker than in on purpose: opening is the thing the player asked to look at.
local OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

--[[
    Where a closed panel waits, as a Y scale of the screen. Anything past 1 is off the bottom
    edge; the margin covers a panel whose anchor sits above its own centre.
]]
local HIDDEN_Y = 1.5

return function(unrest: Types.Unrest): Types.Cleanup
    local bridge = unrest.Bridge
    local Scope = unrest.Scope

    --[[
        Every query in this feature is fenced to this player's own screens.

        Without the fence they match TWICE. `StarterGui.InGame` is tagged, and the tag is read
        off the DataModel rather than off any one screen, so the client adopts the StarterGui
        original as readily as the `PlayerGui` copy Roblox made for this player. The original
        is never rendered and never clicked, so the second set of matches is invisible -- which
        is exactly what makes it expensive to find later.
    ]]
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local lifetime = Scope.scope()

    local reveal = RevealFactory(Scope, {
        Property = "Position",
        Hide = function(resting: any): any
            local home = resting :: UDim2
            return UDim2.new(home.X.Scale, home.X.Offset, HIDDEN_Y, 0)
        end,
        Open = OPEN,
        Close = CLOSE,
    })

    --- Only if nobody has spoken yet: a panel that some other feature already opened should
    --- not be slammed shut by this file merely loading after it.
    if bridge:Peek(Channels.Open) == nil then
        bridge:Publish(Channels.Open, false)
    end

    local frames = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiObject",
        Role = "ServerListPanel",
        Ancestor = playerGui,
    }, {
        --[[
            The opening paint, and it does not animate. A panel adopted while the list is
            already open -- the screen replicated late, or a designer ticked the tag mid-game
            -- should already be there, not slide in as though the player had just asked for it.

            `Added` has to be passed here rather than merged in later with `:Bind`: a merge
            rebinds every element but fires `Added` for none of them, because they had already
            arrived.
        ]]
        Added = function(element: Instance)
            reveal:Adopt(element :: GuiObject, bridge:Peek(Channels.Open) == true)
        end,

        --- Untagged, ignored, reparented away, destroyed, or the query itself torn down.
        Removed = function(element: Instance)
            reveal:Release(element :: GuiObject)
        end,
    })

    local closers = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiButton",
        Role = Vocab.Roles.ServerListClose,
        Ancestor = playerGui,
    }, {
        --- Closing is a state, not a second animation: the same boolean the toggle writes.
        Active = function(): ()
            bridge:Publish(Channels.Open, false)
        end,
    })

    local buttons = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiButton",
        Role = Vocab.Roles.ServerListButton,
        Ancestor = playerGui,
    }, {
        --[[
            The button never touches the panel, and does not know one exists. It flips a
            boolean; what that boolean looks like is `Reveal`, and a second way to open the
            list -- a keybind, a server packet -- is a `Publish` rather than a second animation.
        ]]
        Active = function(): ()
            bridge:Publish(Channels.Open, not bridge:Peek(Channels.Open))
        end,
    })

    --[[
        LIFO: whatever goes in last comes out first. The subscription is last, so teardown
        stops listening before it destroys the queries the listener works over; the two
        sub-features are first, so they come down after the panel that contains them.
    ]]
    Scope.addBulk(
        lifetime,
        Info(unrest, playerGui),
        Directory(unrest, playerGui),
        reveal,
        closers,
        buttons,
        frames,
        bridge:Subscribe(Channels.Open, function(value: any)
            local open = value == true
            reveal:Apply(open)

            --- A shut list has nothing selected. Leaving the selection behind would reopen
            --- the panel with a side panel already hanging off it.
            if not open then
                bridge:Publish(Channels.Selected, "")
            end
        end)
    )

    return function(): ()
        Scope.destroy(lifetime)
    end
end
