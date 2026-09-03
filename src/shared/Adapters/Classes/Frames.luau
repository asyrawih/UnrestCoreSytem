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
    Unrest / Adapters / Classes / Frames

    The non-interactive `GuiObject` containers and displays: `Frame`, `ScrollingFrame`,
    `CanvasGroup`, `ViewportFrame`, `VideoFrame` and `ImageLabel`.

    None of them adds an event of its own -- Hover/Unhover/Press/Release all arrive from
    `GuiObject` -- so each is a property allowlist plus, where the class has one obvious
    value, a `ValueProperty` that gives it `Changed`. `ScrollingFrame` is the interesting
    case: its value is `CanvasPosition`, so a scroll position can drive framework state
    without anybody polling it.

    A `Frame` has no `ValueProperty` on purpose. Binding `Changed` to one is a mistake worth
    hearing about, not a subscription to nothing.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

local Frame: Types.Adapter = {
    ClassName = "Frame",
    Extends = "GuiObject",
    Bindable = {
        Style = true,
    },
}

local ScrollingFrame: Types.Adapter = {
    ClassName = "ScrollingFrame",
    Extends = "GuiObject",
    Bindable = {
        CanvasPosition = true,
        CanvasSize = true,
        AutomaticCanvasSize = true,
        ScrollingEnabled = true,
        ScrollingDirection = true,
        ScrollBarThickness = true,
        ScrollBarImageColor3 = true,
        ScrollBarImageTransparency = true,
        ElasticBehavior = true,
        HorizontalScrollBarInset = true,
        VerticalScrollBarInset = true,
    },
    ValueProperty = "CanvasPosition",
}

local CanvasGroup: Types.Adapter = {
    ClassName = "CanvasGroup",
    Extends = "GuiObject",
    Bindable = {
        GroupColor3 = true,
        GroupTransparency = true,
    },
    ValueProperty = "GroupTransparency",
}

local ViewportFrame: Types.Adapter = {
    ClassName = "ViewportFrame",
    Extends = "GuiObject",
    Bindable = {
        Ambient = true,
        CurrentCamera = true,
        ImageColor3 = true,
        ImageTransparency = true,
        LightColor = true,
        LightDirection = true,
    },
}

local VideoFrame: Types.Adapter = {
    ClassName = "VideoFrame",
    Extends = "GuiObject",
    Bindable = {
        Video = true,
        Looped = true,
        Playing = true,
        TimePosition = true,
        Volume = true,
    },
    ValueProperty = "Video",
}

local ImageLabel: Types.Adapter = {
    ClassName = "ImageLabel",
    Extends = "GuiObject",
    Bindable = Common.properties(Common.Image),
    ValueProperty = "Image",
}

return table.freeze({ Frame, ScrollingFrame, CanvasGroup, ViewportFrame, VideoFrame, ImageLabel } :: { Types.Adapter })
