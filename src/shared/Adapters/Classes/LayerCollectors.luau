--!strict
--[[
    Unrest / Adapters / Classes / LayerCollectors

    The containers that put 2D UI somewhere: `ScreenGui`, `SurfaceGui` and `BillboardGui`.

    A `LayerCollector` is a `GuiBase2d` but *not* a `GuiObject`, which is exactly why the
    pointer events live one branch away. A ScreenGui has no `MouseEnter` and no
    `BackgroundColor3`; declaring either here would be a promise the class cannot keep, and
    the framework would rather fail at bind time than connect to nothing.

    What these classes do offer is visibility (`Enabled`) and, for the world-space two,
    what they are attached to (`Adornee`) -- both bindable, so a channel can show or move a
    whole screen without any code.
]]

local Types = require(script.Parent.Parent.Types)

local LayerCollector: Types.Adapter = {
    ClassName = "LayerCollector",
    Extends = "GuiBase2d",
    Bindable = {
        Enabled = true,
        ResetOnSpawn = true,
        ZIndexBehavior = true,
    },
    ValueProperty = "Enabled",
}

local ScreenGui: Types.Adapter = {
    ClassName = "ScreenGui",
    Extends = "LayerCollector",
    Bindable = {
        DisplayOrder = true,
        IgnoreGuiInset = true,
        ClipToDeviceSafeArea = true,
        SafeAreaCompatibility = true,
        ScreenInsets = true,
    },
}

local SurfaceGui: Types.Adapter = {
    ClassName = "SurfaceGui",
    Extends = "LayerCollector",
    Bindable = {
        Adornee = true,
        Face = true,
        AlwaysOnTop = true,
        Brightness = true,
        LightInfluence = true,
        MaxDistance = true,
        PixelsPerStud = true,
        SizingMode = true,
        CanvasSize = true,
        ClipsDescendants = true,
    },
}

local BillboardGui: Types.Adapter = {
    ClassName = "BillboardGui",
    Extends = "LayerCollector",
    Bindable = {
        Adornee = true,
        Size = true,
        AlwaysOnTop = true,
        Brightness = true,
        LightInfluence = true,
        MaxDistance = true,
        ExtentsOffset = true,
        ExtentsOffsetWorldSpace = true,
        StudsOffset = true,
        StudsOffsetWorldSpace = true,
        ClipsDescendants = true,
    },
}

return table.freeze({ LayerCollector, ScreenGui, SurfaceGui, BillboardGui } :: { Types.Adapter })
