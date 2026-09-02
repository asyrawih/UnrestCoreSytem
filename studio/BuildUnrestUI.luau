--!nocheck
--[[
    Build Unrest UI -- run inside Roblox Studio.

    Creates a worked example screen in StarterGui, tagged and attributed so the framework
    adopts it the moment the game runs. Nothing here is framework code: this is a seed. Once
    it has run, the UI is ordinary Studio instances that you own -- move them, restyle them,
    rename them, delete the ones you do not want. The framework only ever reads the tag and
    the `Unrest*` attributes.

    Two ways to run it:

      * Command bar -- paste this whole file in and press Enter.
      * Plugin      -- drop this file in your Studio plugins folder. It adds a toolbar
                       button, and re-running it rebuilds the screen from scratch.

    Re-running is safe: an existing `UnrestDemo` is removed first, and the whole build is a
    single undo step.

    On how little is written here. An earlier version of this file set 32 attributes across
    these nine elements. It now sets 11, and two of the nine carry none at all. Nothing was
    given up:

      * `UnrestGroup` is set once, on the ScreenGui, and inherited by everything under it;
      * a preset name stands in for the bundle of attributes it implies, so "what a music
        toggle is" is decided once in `Presets.luau` rather than retyped per button;
      * `UnrestRole` is omitted wherever it would just repeat the instance's own name, which
        `Role` already falls back to.

    What is left is the one fact only the author knows: which command this button sends, and
    with what payload.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local SCREEN_NAME = "UnrestDemo"
local TAG = "Unrest"

-- Palette lifted from the design board: near-black ground, light panels, violet accent.
local PANEL = Color3.fromRGB(208, 208, 210)
local CHIP = Color3.fromRGB(212, 212, 216)
local ACCENT = Color3.fromRGB(124, 58, 237)
local ON_LIGHT = Color3.fromRGB(28, 28, 32)
local ON_DARK = Color3.fromRGB(244, 244, 246)

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number): UICorner
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function padding(parent: Instance, x: number, y: number): UIPadding
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, x)
    p.PaddingRight = UDim.new(0, x)
    p.PaddingTop = UDim.new(0, y)
    p.PaddingBottom = UDim.new(0, y)
    p.Parent = parent
    return p
end

local function list(parent: Instance, horizontal: boolean, gap: number): UIListLayout
    local l = Instance.new("UIListLayout")
    l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap)
    l.Parent = parent
    return l
end

--[[
    The only framework-facing step in this whole file: add the tag, then write the
    attributes. Everything else is ordinary Studio work.
]]
local function manage(instance: Instance, attributes: { [string]: any }): Instance
    for key, value in attributes do
        instance:SetAttribute(key, value)
    end
    CollectionService:AddTag(instance, TAG)
    return instance
end

local function chip(name: string, text: string, order: number, accent: boolean): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Text = text
    button.LayoutOrder = order
    button.AutomaticSize = Enum.AutomaticSize.XY
    button.Size = UDim2.fromOffset(0, 34)
    button.BackgroundColor3 = if accent then ACCENT else CHIP
    button.TextColor3 = if accent then ON_DARK else ON_LIGHT
    button.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
    button.TextSize = 14
    button.AutoButtonColor = true
    button.BorderSizePixel = 0
    corner(button, 17)
    padding(button, 16, 8)
    return button
end

local function label(name: string, text: string, order: number, size: number, color: Color3): TextLabel
    local l = Instance.new("TextLabel")
    l.Name = name
    l.Text = text
    l.LayoutOrder = order
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, size + 10)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = color
    l.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
    l.TextSize = size
    return l
end

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

local function build(): ScreenGui
    local existing = StarterGui:FindFirstChild(SCREEN_NAME)
    if existing then
        existing:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = SCREEN_NAME
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    ----------------------------------------------------------------------------
    -- Panel. The board's "Dynamic UI" box.
    ----------------------------------------------------------------------------

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.44)
    panel.Size = UDim2.fromOffset(380, 0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.BackgroundColor3 = PANEL
    panel.BorderSizePixel = 0
    panel.Parent = screen
    corner(panel, 14)
    padding(panel, 18, 18)

    local panelList = list(panel, false, 10)
    panelList.HorizontalAlignment = Enum.HorizontalAlignment.Left

    --[[
        Tagged, and that is all. It does nothing on its own and exists so the
        `Group = "MainMenu"` query has a container to count -- the group arrives by
        inheritance from the ScreenGui, and `Role` falls back to the instance name.
    ]]
    manage(panel, {})

    label("Title", "Dynamic UI", 1, 20, ON_LIGHT).Parent = panel

    --[[
        Attribute-only state display. No code binds this label: the channel value arrives
        through the Bridge and the ElementManager writes it into `Text` using the format.
        `Music.NowPlaying` is retained, so this paints correctly even if the value was
        published long before the screen loaded.
    ]]
    local nowPlaying = manage(label("NowPlaying", "Now playing: --", 2, 15, ON_LIGHT), {
        UnrestPreset = "NowPlayingLabel",
    })
    nowPlaying.Parent = panel

    local row = Instance.new("Frame")
    row.Name = "Row"
    row.LayoutOrder = 3
    row.AutomaticSize = Enum.AutomaticSize.XY
    row.Size = UDim2.fromOffset(0, 34)
    row.BackgroundTransparency = 1
    row.Parent = panel
    local rowList = list(row, true, 8)
    rowList.HorizontalAlignment = Enum.HorizontalAlignment.Left

    --[[
        Attribute-only commands. Each of these is the same `Bridge:Dispatch` a script would
        make, so the command contract still decides whether the server accepts it. Setting
        `UnrestCommand = "Music.ForceStopAll"` here would be refused: that contract does not
        set `AllowClient`, and an attribute grants no privilege.
    ]]
    manage(chip("StopMusic", "Stop", 1, false), { UnrestPreset = "MusicStop" }).Parent = row

    --[[
        Two buttons, one preset, and the only thing that differs between them stays on the
        element. A preset is a default, so `UnrestPayload` here overrides nothing and
        completes the pair.
    ]]
    local volumeDown = manage(chip("VolumeDown", "Vol 20%", 2, false), {
        UnrestPreset = "VolumeButton",
        UnrestPayload = 0.2,
    })
    volumeDown.Parent = row

    local volumeUp = manage(chip("VolumeUp", "Vol 80%", 3, false), {
        UnrestPreset = "VolumeButton",
        UnrestPayload = 0.8,
    })
    volumeUp.Parent = row

    label("Hint", "Tagged Unrest. Edit freely -- the framework only reads the tag.", 4, 12, ON_LIGHT).Parent = panel

    ----------------------------------------------------------------------------
    -- Dock. The chip row from the board, DxChips X included.
    ----------------------------------------------------------------------------

    local dock = Instance.new("Frame")
    dock.Name = "Dock"
    dock.AnchorPoint = Vector2.new(0.5, 1)
    dock.Position = UDim2.new(0.5, 0, 1, -28)
    dock.Size = UDim2.fromOffset(0, 34)
    dock.AutomaticSize = Enum.AutomaticSize.XY
    dock.BackgroundTransparency = 1
    dock.Parent = screen
    list(dock, true, 10)

    --[[
        No `UnrestCommand` on purpose. The client bootstrap binds this one through
        `Unrest:Query` because its behaviour depends on current state -- it reads the
        NowPlaying channel and picks play or stop. That is the escape hatch an attribute
        cannot express, and `UnrestRole` is how the query finds it without depending on the
        instance name.
    ]]
    manage(chip("ToggleMenu", "DxChips X", 1, true), {}).Parent = dock

    manage(chip("MusicChip", "Music: --", 2, false), { UnrestPreset = "MusicToggle" }).Parent = dock

    --[[
        `UnrestCooldown` is a client-side debounce and advisory only. The binding rate limit
        that actually protects the server is `Dance.Play`'s contract: 3 calls per 2 seconds,
        per player, enforced server-side.
    ]]
    local danceChip = manage(chip("DanceChip", "Dance", 3, false), {
        UnrestPreset = "DanceButton",
        UnrestPayload = "Wave",
    })
    danceChip.Parent = dock

    manage(chip("StopDance", "Stop dance", 4, false), { UnrestPreset = "DanceStop" }).Parent = dock

    --[[
        One attribute for the whole screen. Every tagged descendant inherits it, so
        `Group = "MainMenu"` selects the lot without any of them naming it.
    ]]
    screen:SetAttribute("UnrestGroup", "MainMenu")

    screen.Parent = StarterGui
    return screen
end

--------------------------------------------------------------------------------
-- Entry point. One undo step whether this runs as a plugin or from the command bar.
--------------------------------------------------------------------------------

local function run(): ()
    local okRec, recording = pcall(function()
        return ChangeHistoryService:TryBeginRecording("Build Unrest UI")
    end)
    if not okRec then
        recording = nil
    end
    local ok, result = pcall(build)

    if recording then
        ChangeHistoryService:FinishRecording(
            recording,
            if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
        )
    end

    if not ok then
        error(`[BuildUnrestUI] failed: {result}`, 0)
    end

    Selection:Set({ result })
    print(`[BuildUnrestUI] built StarterGui.{SCREEN_NAME}. 9 tagged elements, 11 attributes, ready for Play.`)
end

if plugin then
    local toolbar = plugin:CreateToolbar("Unrest")
    local button = toolbar:CreateButton("Build UI", "Rebuild the Unrest demo screen in StarterGui", "")
    button.ClickableWhenViewportHidden = true
    button.Click:Connect(run)
else
    run()
end
