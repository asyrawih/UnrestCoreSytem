--!nocheck
--[[
    Build Unrest UI -- run inside Roblox Studio.

    The smallest screen that shows the whole API:

        Panel (Frame)          <- the only tag. It cascades to everything below.
          ToggleMenu (Button)  <- no attributes at all; bound from code by its name
          Play (Button)        <- two attributes, no code
          NowPlaying (Label)   <- three attributes, no code

    One tag and five attributes. That is the entire surface: tag a container, wire the simple
    things in Studio, and drop into code only for behaviour an attribute cannot express.

    Two ways to run it:

      * Command bar -- paste this whole file in and press Enter.
      * Plugin      -- drop this file in your Studio plugins folder for a toolbar button.

    Re-running is safe: an existing `UnrestDemo` is removed first, and the whole build is one
    undo step. Afterwards the screen is ordinary Studio instances that you own -- restyle it,
    rename things, add buttons. The framework only ever reads the tag and the attributes.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local SCREEN_NAME = "UnrestDemo"
local TAG = "Unrest"

local PANEL = Color3.fromRGB(208, 208, 210)
local ACCENT = Color3.fromRGB(124, 58, 237)
local ON_LIGHT = Color3.fromRGB(28, 28, 32)
local ON_DARK = Color3.fromRGB(244, 244, 246)

local function button(name: string, text: string, order: number, accent: boolean): TextButton
    local instance = Instance.new("TextButton")
    instance.Name = name
    instance.Text = text
    instance.LayoutOrder = order
    instance.Size = UDim2.new(1, 0, 0, 36)
    instance.BackgroundColor3 = if accent then ACCENT else Color3.fromRGB(232, 232, 235)
    instance.TextColor3 = if accent then ON_DARK else ON_LIGHT
    instance.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
    instance.TextSize = 14
    instance.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = instance

    return instance
end

local function build(): ScreenGui
    local existing = StarterGui:FindFirstChild(SCREEN_NAME)
    if existing then
        existing:Destroy()
    end

    local screen = Instance.new("ScreenGui")
    screen.Name = SCREEN_NAME
    screen.ResetOnSpawn = false

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(240, 0)
    panel.AutomaticSize = Enum.AutomaticSize.Y
    panel.BackgroundColor3 = PANEL
    panel.BorderSizePixel = 0
    panel.Parent = screen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = panel

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.PaddingTop = UDim.new(0, 16)
    padding.PaddingBottom = UDim.new(0, 16)
    padding.Parent = panel

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = panel

    --[[
        The only tag in this file. It manages the Frame and every GuiObject under it, so the
        two buttons and the label below are opted in without being tagged themselves. The
        UIListLayout, UIPadding and UICorner are not swept up -- they lay things out and have
        nothing to bind.
    ]]
    CollectionService:AddTag(panel, TAG)

    --[[
        No attributes. The client bootstrap binds this one with `Unrest:Query`, because its
        behaviour depends on current state: it plays or stops depending on what is already
        playing, and a fixed `UnrestCommand` cannot express "it depends".

        It is found by role, and role falls back to `Instance.Name` -- so naming the button
        `ToggleMenu` is the whole binding.
    ]]
    local toggle = button("ToggleMenu", "Toggle music", 1, true)
    toggle.Parent = panel

    --[[
        Two attributes, no code. Activating this dispatches through the Bridge exactly as a
        script would, which means the command's contract still decides whether a client may
        ask for it -- an attribute grants no privilege.
    ]]
    local play = button("Play", "Play Lobby", 2, false)
    play:SetAttribute("UnrestCommand", "Music.Play")
    play:SetAttribute("UnrestPayload", "Lobby")
    play.Parent = panel

    --[[
        Three attributes, no code. The channel is retained, so this label paints the current
        track on its first frame even if the value was published long before the screen
        loaded.

        `UnrestPreset = "NowPlayingLabel"` is these three under one name; see Presets.luau.
    ]]
    local label = Instance.new("TextLabel")
    label.Name = "NowPlaying"
    label.LayoutOrder = 3
    label.Size = UDim2.new(1, 0, 0, 20)
    label.BackgroundTransparency = 1
    label.Text = "Nothing playing"
    label.TextColor3 = ON_LIGHT
    label.FontFace = Font.fromEnum(Enum.Font.Gotham)
    label.TextSize = 13
    label:SetAttribute("UnrestChannel", "Music.NowPlaying")
    label:SetAttribute("UnrestBind", "Text")
    label:SetAttribute("UnrestFormat", "Now playing: {value}")
    label.Parent = panel

    screen.Parent = StarterGui
    return screen
end

local function run(): ()
    local recording = ChangeHistoryService:TryBeginRecording("Build Unrest UI")
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
    print(`[BuildUnrestUI] built StarterGui.{SCREEN_NAME}: 1 tag, 5 attributes, 3 elements.`)
end

if plugin then
    local toolbar = plugin:CreateToolbar("Unrest")
    local toolbarButton = toolbar:CreateButton("Build UI", "Rebuild the Unrest example screen", "")
    toolbarButton.ClickableWhenViewportHidden = true
    toolbarButton.Click:Connect(run)
else
    run()
end
