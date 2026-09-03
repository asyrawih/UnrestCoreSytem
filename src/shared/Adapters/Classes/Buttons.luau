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
    Unrest / Adapters / Classes / Buttons

    `GuiButton` and its two concrete forms.

    `GuiButton` is where "activation" becomes a real thing rather than a guess: `Activated`
    already folds mouse, touch and gamepad into one event and already respects `Modal` and
    `Active`, so `Active` binds to it rather than to `MouseButton1Click`. `Secondary` is the
    right-click, which only the mouse has -- it simply never fires on touch, which is the
    honest behaviour.

    Press/Release/Hover/Unhover are inherited from `GuiObject` and are not repeated here.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

local GuiButton: Types.Adapter = {
    ClassName = "GuiButton",
    Extends = "GuiObject",

    Events = {
        Active = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiButton).Activated:Connect(function()
                invoke(nil)
            end)
        end,

        Secondary = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiButton).MouseButton2Click:Connect(function()
                invoke(nil)
            end)
        end,
    },

    Bindable = {
        AutoButtonColor = true,
        Modal = true,
        Selected = true,
    },
}

local TextButton: Types.Adapter = {
    ClassName = "TextButton",
    Extends = "GuiButton",
    Bindable = Common.properties(Common.Text),
    ValueProperty = "Text",
}

local ImageButton: Types.Adapter = {
    ClassName = "ImageButton",
    Extends = "GuiButton",
    Bindable = Common.properties(Common.Image, {
        HoverImage = true,
        PressedImage = true,
    }),
    ValueProperty = "Image",
}

return table.freeze({ GuiButton, TextButton, ImageButton } :: { Types.Adapter })
