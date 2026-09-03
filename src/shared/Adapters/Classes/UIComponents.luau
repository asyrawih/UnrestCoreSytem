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
    Unrest / Adapters / Classes / UIComponents

    Everything under `UIBase`: the layouts, the constraints, and the decorators.

    These classes have no events at all -- nothing hovers a `UIPadding` -- so every adapter
    here is a property allowlist and nothing else. That is not a gap: it is the reason the
    allowlist exists. A designer can point `UnrestChannel` at a `UIListLayout.Padding` or a
    `UIStroke.Color` and animate a whole menu from framework state, while `UnrestCommand` on
    the same object fails loudly because a layout cannot be activated.

    The chain mirrors Roblox's own (`UIBase` -> `UIComponent` -> `UILayout` ->
    `UIGridStyleLayout` -> ...), so an unregistered `UI*` class the framework has never
    heard of still resolves to the nearest ancestor rather than to nothing.

    Only `UICorner` and `UIScale` declare a `ValueProperty`, because only they have one
    obvious value. `ValueProperty` is what gives a class its `Changed` handler, and a
    `Changed` that fires for whichever of a UIListLayout's nine properties somebody picked
    as "the" one would be a coin flip dressed up as an event.
]]

local Types = require(script.Parent.Parent.Types)

local UIBase: Types.Adapter = {
    ClassName = "UIBase",
}

local UIComponent: Types.Adapter = {
    ClassName = "UIComponent",
    Extends = "UIBase",
}

--------------------------------------------------------------------------------
-- Layouts
--------------------------------------------------------------------------------

local UILayout: Types.Adapter = {
    ClassName = "UILayout",
    Extends = "UIComponent",
}

local UIGridStyleLayout: Types.Adapter = {
    ClassName = "UIGridStyleLayout",
    Extends = "UILayout",
    Bindable = {
        FillDirection = true,
        HorizontalAlignment = true,
        VerticalAlignment = true,
        SortOrder = true,
    },
}

local UIListLayout: Types.Adapter = {
    ClassName = "UIListLayout",
    Extends = "UIGridStyleLayout",
    Bindable = {
        Padding = true,
        Wraps = true,
        ItemLineAlignment = true,
        HorizontalFlex = true,
        VerticalFlex = true,
    },
}

local UIGridLayout: Types.Adapter = {
    ClassName = "UIGridLayout",
    Extends = "UIGridStyleLayout",
    Bindable = {
        CellSize = true,
        CellPadding = true,
        FillDirectionMaxCells = true,
        StartCorner = true,
    },
}

local UIPageLayout: Types.Adapter = {
    ClassName = "UIPageLayout",
    Extends = "UIGridStyleLayout",
    Bindable = {
        Animated = true,
        Circular = true,
        EasingDirection = true,
        EasingStyle = true,
        GamepadInputEnabled = true,
        Padding = true,
        ScrollWheelInputEnabled = true,
        TouchInputEnabled = true,
        TweenTime = true,
    },
}

local UITableLayout: Types.Adapter = {
    ClassName = "UITableLayout",
    Extends = "UIGridStyleLayout",
    Bindable = {
        FillEmptySpaceColumns = true,
        FillEmptySpaceRows = true,
        MajorAxis = true,
        Padding = true,
    },
}

--------------------------------------------------------------------------------
-- Constraints
--------------------------------------------------------------------------------

local UIConstraint: Types.Adapter = {
    ClassName = "UIConstraint",
    Extends = "UIComponent",
}

local UIAspectRatioConstraint: Types.Adapter = {
    ClassName = "UIAspectRatioConstraint",
    Extends = "UIConstraint",
    Bindable = {
        AspectRatio = true,
        AspectType = true,
        DominantAxis = true,
    },
}

local UISizeConstraint: Types.Adapter = {
    ClassName = "UISizeConstraint",
    Extends = "UIConstraint",
    Bindable = {
        MaxSize = true,
        MinSize = true,
    },
}

local UITextSizeConstraint: Types.Adapter = {
    ClassName = "UITextSizeConstraint",
    Extends = "UIConstraint",
    Bindable = {
        MaxTextSize = true,
        MinTextSize = true,
    },
}

--------------------------------------------------------------------------------
-- Decorators
--------------------------------------------------------------------------------

local UIPadding: Types.Adapter = {
    ClassName = "UIPadding",
    Extends = "UIComponent",
    Bindable = {
        PaddingTop = true,
        PaddingBottom = true,
        PaddingLeft = true,
        PaddingRight = true,
    },
}

local UICorner: Types.Adapter = {
    ClassName = "UICorner",
    Extends = "UIComponent",
    Bindable = {
        CornerRadius = true,
    },
    ValueProperty = "CornerRadius",
}

local UIGradient: Types.Adapter = {
    ClassName = "UIGradient",
    Extends = "UIComponent",
    Bindable = {
        Color = true,
        Enabled = true,
        Offset = true,
        Rotation = true,
        Transparency = true,
    },
}

local UIStroke: Types.Adapter = {
    ClassName = "UIStroke",
    Extends = "UIComponent",
    Bindable = {
        ApplyStrokeMode = true,
        Color = true,
        Enabled = true,
        LineJoinMode = true,
        Thickness = true,
        Transparency = true,
    },
}

local UIScale: Types.Adapter = {
    ClassName = "UIScale",
    Extends = "UIComponent",
    Bindable = {
        Scale = true,
    },
    ValueProperty = "Scale",
}

local UIFlexItem: Types.Adapter = {
    ClassName = "UIFlexItem",
    Extends = "UIComponent",
    Bindable = {
        FlexMode = true,
        GrowRatio = true,
        ShrinkRatio = true,
        ItemLineAlignment = true,
        FillEmptySpace = true,
    },
}

return table.freeze({
    UIBase,
    UIComponent,
    UILayout,
    UIGridStyleLayout,
    UIListLayout,
    UIGridLayout,
    UIPageLayout,
    UITableLayout,
    UIConstraint,
    UIAspectRatioConstraint,
    UISizeConstraint,
    UITextSizeConstraint,
    UIPadding,
    UICorner,
    UIGradient,
    UIStroke,
    UIScale,
    UIFlexItem,
} :: { Types.Adapter })
