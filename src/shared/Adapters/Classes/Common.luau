--!strict
--[[
    Unrest / Adapters / Classes / Common

    Shared building blocks for the class families. Not an adapter itself -- `Adapters/init`
    requires each family module by name, so nothing here is ever mistaken for one.

    Two Roblox classes that render text (`TextLabel`, `TextButton`, `TextBox`) have no common
    ancestor: they descend from `GuiObject` through `GuiLabel` and `GuiButton` respectively.
    The property allowlist they share therefore cannot be inherited through `Extends`, so it
    is written once here and merged into each of them.
]]

local Common = {}

--- Merges property allowlists into a fresh table. Later sources win.
function Common.properties(...: { [string]: boolean }): { [string]: boolean }
    local merged: { [string]: boolean } = {}
    for index = 1, select("#", ...) do
        local source = (select(index, ...) :: any) :: { [string]: boolean }
        for key, allowed in source do
            merged[key] = allowed
        end
    end
    return merged
end

--- Everything a `TextLabel` / `TextButton` / `TextBox` renders text with.
Common.Text = table.freeze({
    Text = true,
    TextColor3 = true,
    TextTransparency = true,
    TextScaled = true,
    TextSize = true,
    TextWrapped = true,
    TextTruncate = true,
    TextXAlignment = true,
    TextYAlignment = true,
    TextStrokeColor3 = true,
    TextStrokeTransparency = true,
    RichText = true,
    FontFace = true,
    LineHeight = true,
    MaxVisibleGraphemes = true,
})

--- Everything an `ImageLabel` / `ImageButton` renders an image with.
Common.Image = table.freeze({
    Image = true,
    ImageColor3 = true,
    ImageTransparency = true,
    ImageRectOffset = true,
    ImageRectSize = true,
    ScaleType = true,
    SliceCenter = true,
    SliceScale = true,
    TileSize = true,
    ResampleMode = true,
})

return table.freeze(Common)
