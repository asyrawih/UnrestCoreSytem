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
    Unrest / Adapters / Classes / GuiBase

    The root of the 2D UI hierarchy: `GuiBase2d` and `GuiObject`.

    `GuiBase2d` is the common ancestor of *both* on-screen objects and the containers that
    host them (`LayerCollector`), so it carries nothing but the handful of properties both
    genuinely share. Everything a pointer can do lives one level down, on `GuiObject`: a
    ScreenGui has no MouseEnter, and pretending otherwise would put a binder on a class that
    cannot honour it.

    Every other 2D adapter in the framework reaches these two through `Extends`, so a
    handler or a bindable property added here is added everywhere at once.
]]

local Types = require(script.Parent.Parent.Types)

--[[
    Press/Release are pointer-down and pointer-up, which Roblox only exposes through the raw
    InputBegan/InputEnded firehose. Filtering to the primary mouse button and touch is what
    turns that firehose back into the event a designer expects; keyboard and gamepad input
    that happens to be routed at the element is deliberately not a "press".
]]
local function isPointer(input: InputObject): boolean
    local kind = input.UserInputType
    return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

local GuiBase2d: Types.Adapter = {
    ClassName = "GuiBase2d",
    Bindable = {
        AutoLocalize = true,
        Active = true,
        Selectable = true,
    },
}

local GuiObject: Types.Adapter = {
    ClassName = "GuiObject",
    Extends = "GuiBase2d",

    Events = {
        Hover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiObject).MouseEnter:Connect(function()
                invoke(nil)
            end)
        end,

        Unhover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiObject).MouseLeave:Connect(function()
                invoke(nil)
            end)
        end,

        Press = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiObject).InputBegan:Connect(function(input: InputObject)
                if isPointer(input) then
                    invoke(nil)
                end
            end)
        end,

        Release = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: GuiObject).InputEnded:Connect(function(input: InputObject)
                if isPointer(input) then
                    invoke(nil)
                end
            end)
        end,
    },

    Bindable = {
        Visible = true,
        BackgroundColor3 = true,
        BackgroundTransparency = true,
        BorderColor3 = true,
        BorderSizePixel = true,
        Position = true,
        Size = true,
        AnchorPoint = true,
        AutomaticSize = true,
        Rotation = true,
        LayoutOrder = true,
        ZIndex = true,
        ClipsDescendants = true,
    },
}

return table.freeze({ GuiBase2d, GuiObject } :: { Types.Adapter })
