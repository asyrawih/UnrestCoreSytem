--!strict
--[[
    UnrestClient -- StarterPlayer.StarterPlayerScripts.UnrestClient

    Client bootstrap and the framework's own worked example. It does four things:

      1. boots Unrest;
      2. builds a host ScreenGui (the app owns its screen, the framework does not);
      3. registers the whiteboard's query *before* the element it selects exists, proving the
         CollectionService binding is live rather than a one-shot scan;
      4. mounts DxChips X components and lets the Bridge carry every interaction to Core.

    Nothing here reaches into a system table. Everything goes through Unrest:Query,
    Unrest:Mount and Unrest.Bridge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Unrest")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Types = require(ReplicatedStorage.Unrest.Types)
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Host surface
--------------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "UnrestDemo"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local row = Instance.new("Frame")
row.Name = "ChipRow"
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -32)
row.Size = UDim2.fromOffset(0, 0)
row.AutomaticSize = Enum.AutomaticSize.XY
row.BackgroundTransparency = 1
row.Parent = screen

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 10)
rowLayout.Parent = row

screen.Parent = playerGui

--------------------------------------------------------------------------------
-- The whiteboard sketch, verbatim in intent -- registered BEFORE anything matches it.
--------------------------------------------------------------------------------

local toggle = unrest:Query({
    Tag = Constants.Tag, -- "Unrest"
    Selector = "TextButton", -- is:A("TextButton")
    Name = "ToggleMenu",
}, {
    Active = function(element: Instance)
        print(`[UnrestClient] activated {element.Name}`)
        unrest.Bridge:Dispatch(Constants.Commands.MusicPlay, "Lobby")
    end,

    Hover = function(element: Instance)
        print(`[UnrestClient] hovering {element.Name}`)
    end,

    Unhover = function(element: Instance)
        print(`[UnrestClient] left {element.Name}`)
    end,

    Added = function(element: Instance)
        -- Fires for elements tagged long after this query was created.
        print(`[UnrestClient] query matched {element:GetFullName()}`)
    end,
})

--------------------------------------------------------------------------------
-- Components. These mount *after* the query above, and it picks them up anyway.
--------------------------------------------------------------------------------

local toggleProps: Types.ChipProps = {
    Name = "ToggleMenu",
    Text = "Toggle Menu",
    Selected = true,
}
unrest:Mount("DxChipsX", toggleProps, row)

local danceProps: Types.ChipProps = {
    Name = "DanceChip",
    Text = "Dance",
    Color = Color3.fromRGB(96, 132, 240),
    Removable = true,
}
unrest:Mount("DxChipsX", danceProps, row)

local musicProps: Types.ChipProps = {
    Name = "MusicChip",
    Text = "Music: off",
    Color = Color3.fromRGB(52, 56, 78),
}
local musicChip = unrest:Mount("DxChipsX", musicProps, row)

-- The query above was created before any of these existed, and already sees the match.
print(`[UnrestClient] ToggleMenu query matches {toggle:Count()} element(s)`)

--------------------------------------------------------------------------------
-- Wiring. UI -> Core is a Dispatch; Core -> UI is a Subscribe. Never a direct call.
--------------------------------------------------------------------------------

unrest:Query({ Tag = Constants.Tag, Selector = "TextButton", Name = "DanceChip" }, {
    Active = function()
        unrest.Bridge:Dispatch(Constants.Commands.DancePlay, "Dance")
    end,
})

unrest:Query({ Tag = Constants.Tag, Selector = "TextButton", Name = "MusicChip" }, {
    Active = function()
        local playing = unrest.Bridge:Peek(Constants.Channels.NowPlaying)
        if playing == nil then
            unrest.Bridge:Dispatch(Constants.Commands.MusicPlay, "Dancefloor")
        else
            unrest.Bridge:Dispatch(Constants.Commands.MusicStop, nil)
        end
    end,
})

unrest.Bridge:Subscribe(Constants.Channels.NowPlaying, function(value: any)
    local playing = if typeof(value) == "string" then value else nil
    musicChip:Update({
        Text = if playing ~= nil then `Music: {playing}` else "Music: off",
        Selected = playing ~= nil,
    })
end)

print(`[UnrestClient] Unrest {unrest.Version} ready -- systems: {table.concat(unrest.Core:List(), ", ")}`)
