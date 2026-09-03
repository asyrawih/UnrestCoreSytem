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
    Unrest / Adapters / Classes / Text

    `TextLabel` and `TextBox`.

    Both declare `ValueProperty = "Text"`, which is what makes `Changed` exist for them at
    all: the registry synthesises a `Changed` binder from `ValueProperty` when an adapter
    does not write one by hand, so a label reports edits without either class needing to
    describe the same `GetPropertyChangedSignal` twice.

    `TextBox` is the only 2D class that can hold keyboard focus, so `Focus`, `Blur` and
    `Submit` live here and nowhere else. `Submit` is deliberately *not* every FocusLost:
    clicking away is not a commit, so only `enterPressed` fires it, and it carries the text
    that was committed.
]]

local Common = require(script.Parent.Common)
local Types = require(script.Parent.Parent.Types)

local TextLabel: Types.Adapter = {
    ClassName = "TextLabel",
    Extends = "GuiObject",
    Bindable = Common.properties(Common.Text),
    ValueProperty = "Text",
}

local TextBox: Types.Adapter = {
    ClassName = "TextBox",
    Extends = "GuiObject",

    Events = {
        Focus = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: TextBox).Focused:Connect(function()
                invoke(nil)
            end)
        end,

        Blur = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            local box = element :: TextBox
            return box.FocusLost:Connect(function()
                invoke(nil)
            end)
        end,

        Submit = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            local box = element :: TextBox
            return box.FocusLost:Connect(function(enterPressed: boolean)
                if enterPressed then
                    invoke(box.Text)
                end
            end)
        end,
    },

    Bindable = Common.properties(Common.Text, {
        ClearTextOnFocus = true,
        MultiLine = true,
        PlaceholderText = true,
        PlaceholderColor3 = true,
        TextEditable = true,
    }),

    ValueProperty = "Text",
}

return table.freeze({ TextLabel, TextBox } :: { Types.Adapter })
