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
    Unrest / Adapters / Classes / Interaction

    `ProximityPrompt` and `ClickDetector`: the two 3D interaction surfaces.

    Neither is a GuiObject and neither draws anything, so strictly speaking they are not UI
    at all. They are here because a designer tags a door prompt `Unrest` for exactly the
    same reason they tag a button, and expects `Active` to mean "the player did the thing"
    in both cases. Making them speak the same handler vocabulary is what lets one query
    select "every activatable element in this room" without caring how it is activated.

    The mapping is deliberate rather than mechanical:

      * `Active`          -- MouseClick / Triggered: the commit.
      * `Hover`/`Unhover` -- MouseHoverEnter/Leave, and PromptShown/PromptHidden, which is
                             a prompt's honest equivalent of "the pointer is on me".
      * `Press`/`Release` -- only the prompt has them (hold-to-activate); a ClickDetector
                             exposes no down/up pair, so binding `Press` to one is an error
                             rather than a lie.

    Both fire on the *server* as well as the client. The framework only adopts on the
    client, so these bindings exist on one side and the events on the other are ignored.
]]

local Types = require(script.Parent.Parent.Types)

local ClickDetector: Types.Adapter = {
    ClassName = "ClickDetector",

    Events = {
        Active = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ClickDetector).MouseClick:Connect(function()
                invoke(nil)
            end)
        end,

        Secondary = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ClickDetector).RightMouseClick:Connect(function()
                invoke(nil)
            end)
        end,

        Hover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ClickDetector).MouseHoverEnter:Connect(function()
                invoke(nil)
            end)
        end,

        Unhover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ClickDetector).MouseHoverLeave:Connect(function()
                invoke(nil)
            end)
        end,
    },

    Bindable = {
        MaxActivationDistance = true,
        CursorIcon = true,
    },
}

local ProximityPrompt: Types.Adapter = {
    ClassName = "ProximityPrompt",

    Events = {
        Active = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ProximityPrompt).Triggered:Connect(function()
                invoke(nil)
            end)
        end,

        Hover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ProximityPrompt).PromptShown:Connect(function()
                invoke(nil)
            end)
        end,

        Unhover = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ProximityPrompt).PromptHidden:Connect(function()
                invoke(nil)
            end)
        end,

        Press = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ProximityPrompt).PromptButtonHoldBegan:Connect(function()
                invoke(nil)
            end)
        end,

        Release = function(element: Instance, invoke: (value: any) -> ()): RBXScriptConnection?
            return (element :: ProximityPrompt).PromptButtonHoldEnded:Connect(function()
                invoke(nil)
            end)
        end,
    },

    Bindable = {
        ActionText = true,
        ObjectText = true,
        Enabled = true,
        HoldDuration = true,
        MaxActivationDistance = true,
        RequiresLineOfSight = true,
        KeyboardKeyCode = true,
        GamepadKeyCode = true,
        ClickablePrompt = true,
        Exclusivity = true,
        Style = true,
        UIOffset = true,
    },
}

return table.freeze({ ClickDetector, ProximityPrompt } :: { Types.Adapter })
