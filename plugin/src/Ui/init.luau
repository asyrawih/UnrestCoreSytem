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
    Unrest Plugin / Ui

    The plugin's own widgets, built in code.

    THIS IS NOT THE RULE THE FRAMEWORK BREAKS. CONVENTIONS forbids building *game* UI in
    source, because the framework's whole thesis is that it adopts screens a designer drew.
    A plugin panel is not a game screen: it lives in a `DockWidgetPluginGui`, it ships inside
    a `.rbxm` that is never mounted into the place, and there is no designer and no Studio
    session in which to draw it. Building it in code is the only way it can exist at all.

    Deliberately plain. No external UI library, no state framework, no virtual tree: a panel
    clears its frame and draws it again. The screens here are dozens of rows, not thousands,
    and a rebuild that cannot go stale is worth more than one that is fast.

    Every constructor takes its parent first and parents immediately, so `LayoutOrder` can be
    assigned from the child count and callers never have to number their rows.
]]

local Theme = require(script.Theme)

local Ui = {}

local COLOR = Enum.StudioStyleGuideColor

Ui.PADDING = 6
Ui.ROW_HEIGHT = 22
Ui.LABEL_WIDTH = 116
Ui.TEXT_SIZE = 14

local FONT = Enum.Font.SourceSans
local FONT_BOLD = Enum.Font.SourceSansSemibold
local MENU_Z = 50

local overlay: Frame? = nil

--- Parents `instance` and gives it the next `LayoutOrder`, so creation order is draw order.
local function place(instance: GuiObject, parent: Instance): ()
    instance.LayoutOrder = #parent:GetChildren()
    instance.Parent = parent
end

local function layout(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
    local list = Instance.new("UIListLayout")
    list.FillDirection = direction
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, padding)
    if direction == Enum.FillDirection.Horizontal then
        list.VerticalAlignment = Enum.VerticalAlignment.Center
    end
    list.Parent = parent
    return list
end

--- Destroys every `GuiObject` under `frame`, leaving its layout and padding in place.
function Ui.clear(frame: Instance): ()
    for _, child in frame:GetChildren() do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

--------------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------------

--- A full-size frame with the dock's own background. One per tab.
function Ui.panel(parent: Instance): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BorderSizePixel = 0
    frame.Visible = false
    Theme.paint(frame, function()
        frame.BackgroundColor3 = Theme.color(COLOR.MainBackground)
    end)
    place(frame, parent)
    return frame
end

--- A vertical scroller with room to breathe. Everything a panel draws goes in one of these.
function Ui.scroll(parent: Instance): ScrollingFrame
    local scroller = Instance.new("ScrollingFrame")
    scroller.Size = UDim2.fromScale(1, 1)
    scroller.BackgroundTransparency = 1
    scroller.BorderSizePixel = 0
    scroller.CanvasSize = UDim2.new()
    scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroller.ScrollBarThickness = 8
    scroller.ScrollingDirection = Enum.ScrollingDirection.Y

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, Ui.PADDING)
    padding.PaddingBottom = UDim.new(0, Ui.PADDING)
    padding.PaddingLeft = UDim.new(0, Ui.PADDING)
    padding.PaddingRight = UDim.new(0, Ui.PADDING + 8)
    padding.Parent = scroller

    layout(scroller, Enum.FillDirection.Vertical, 4)

    Theme.paint(scroller, function()
        scroller.ScrollBarImageColor3 = Theme.color(COLOR.ScrollBar)
    end)

    place(scroller, parent)
    return scroller
end

--- A column that grows with its contents. The building block of every list of rows.
function Ui.column(parent: Instance, padding: number?): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    layout(frame, Enum.FillDirection.Vertical, padding or 4)
    place(frame, parent)
    return frame
end

--- A fixed-height strip laid out left to right. For button groups and badges.
function Ui.row(parent: Instance, height: number?): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, height or Ui.ROW_HEIGHT)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    layout(frame, Enum.FillDirection.Horizontal, 4)
    place(frame, parent)
    return frame
end

--[[
    A labelled row: the name on the left, and an empty slot on the right for whichever editor
    the caller wants. Positioned rather than laid out, because a horizontal `UIListLayout`
    cannot give one child "the rest of the width".
]]
function Ui.field(parent: Instance, name: string): Frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, Ui.ROW_HEIGHT)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0

    local caption = Instance.new("TextLabel")
    caption.Size = UDim2.new(0, Ui.LABEL_WIDTH, 1, 0)
    caption.BackgroundTransparency = 1
    caption.Font = FONT
    caption.TextSize = Ui.TEXT_SIZE
    caption.TextXAlignment = Enum.TextXAlignment.Left
    caption.TextTruncate = Enum.TextTruncate.AtEnd
    caption.Text = name
    Theme.paint(caption, function()
        caption.TextColor3 = Theme.color(COLOR.SubText)
    end)
    caption.Parent = frame

    local slot = Instance.new("Frame")
    slot.Position = UDim2.fromOffset(Ui.LABEL_WIDTH + 4, 0)
    slot.Size = UDim2.new(1, -(Ui.LABEL_WIDTH + 4), 1, 0)
    slot.BackgroundTransparency = 1
    slot.BorderSizePixel = 0
    slot.Parent = frame

    place(frame, parent)
    return slot
end

--- A hairline between sections.
function Ui.separator(parent: Instance): Frame
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.BorderSizePixel = 0
    Theme.paint(line, function()
        line.BackgroundColor3 = Theme.color(COLOR.Border)
    end)
    place(line, parent)
    return line
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function text(parent: Instance, body: string, font: Enum.Font, color: Enum.StudioStyleGuideColor): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Font = font
    label.TextSize = Ui.TEXT_SIZE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextWrapped = true
    label.RichText = false
    label.Text = body
    Theme.paint(label, function()
        label.TextColor3 = Theme.color(color)
    end)
    place(label, parent)
    return label
end

--- A sentence. Wraps, and grows the column it is in.
function Ui.label(parent: Instance, body: string): TextLabel
    return text(parent, body, FONT, COLOR.MainText)
end

--- A section title.
function Ui.heading(parent: Instance, body: string): TextLabel
    local label = text(parent, body, FONT_BOLD, COLOR.BrightText)
    label.Size = UDim2.new(1, 0, 0, Ui.ROW_HEIGHT)
    label.AutomaticSize = Enum.AutomaticSize.None
    label.TextYAlignment = Enum.TextYAlignment.Center
    return label
end

--- Secondary text: sources, counts, the things that explain the line above.
function Ui.note(parent: Instance, body: string): TextLabel
    return text(parent, body, FONT, COLOR.DimmedText)
end

--- A sentence that has to carry a colour: a verdict, a level, a warning.
function Ui.tinted(parent: Instance, body: string, color: Enum.StudioStyleGuideColor): TextLabel
    return text(parent, body, FONT, color)
end

--- A finding's level, or any other word that should carry a colour.
function Ui.badge(parent: Instance, body: string, color: Enum.StudioStyleGuideColor): TextLabel
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(0, 1)
    label.AutomaticSize = Enum.AutomaticSize.X
    label.BackgroundTransparency = 1
    label.Font = FONT_BOLD
    label.TextSize = Ui.TEXT_SIZE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = body
    Theme.paint(label, function()
        label.TextColor3 = Theme.color(color)
    end)
    place(label, parent)
    return label
end

Ui.Color = {
    Error = COLOR.ErrorText,
    Warning = COLOR.WarningText,
    Info = COLOR.InfoText,
    Dim = COLOR.DimmedText,
    Main = COLOR.MainText,
    Sub = COLOR.SubText,
    Link = COLOR.LinkText,
}

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

local function styleButton(button: TextButton): ()
    button.AutoButtonColor = false
    button.BorderSizePixel = 1
    button.Font = FONT
    button.TextSize = Ui.TEXT_SIZE

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = button

    local hovered = false
    local function repaint(): ()
        local modifier = if hovered then Enum.StudioStyleGuideModifier.Hover else Enum.StudioStyleGuideModifier.Default
        button.BackgroundColor3 = Theme.color(COLOR.Button, modifier)
        button.BorderColor3 = Theme.color(COLOR.ButtonBorder, modifier)
        button.TextColor3 = Theme.color(COLOR.ButtonText, modifier)
    end

    Theme.paint(button, repaint)
    button.MouseEnter:Connect(function()
        hovered = true
        repaint()
    end)
    button.MouseLeave:Connect(function()
        hovered = false
        repaint()
    end)
end

--- A push button that sizes itself to its text.
function Ui.button(parent: Instance, body: string, onClick: () -> ()): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(0, Ui.ROW_HEIGHT)
    button.AutomaticSize = Enum.AutomaticSize.X
    button.Text = body
    styleButton(button)
    button.Activated:Connect(onClick)
    place(button, parent)
    return button
end

--- A free-text editor. `onCommit` runs on Enter or on focus loss, never per keystroke.
function Ui.textBox(parent: Instance, value: string, onCommit: (string) -> ()): TextBox
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromScale(1, 1)
    box.BorderSizePixel = 1
    box.ClearTextOnFocus = false
    box.Font = FONT
    box.TextSize = Ui.TEXT_SIZE
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextTruncate = Enum.TextTruncate.AtEnd
    box.Text = value

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)
    pad.Parent = box

    Theme.paint(box, function()
        box.BackgroundColor3 = Theme.color(COLOR.InputFieldBackground)
        box.BorderColor3 = Theme.color(COLOR.InputFieldBorder)
        box.TextColor3 = Theme.color(COLOR.MainText)
        box.PlaceholderColor3 = Theme.color(COLOR.DimmedText)
    end)

    box.FocusLost:Connect(function()
        onCommit(box.Text)
    end)

    place(box, parent)
    return box
end

--[[
    A read-only multi-line box, for text meant to be selected and copied.

    It grows to its content and lets the scroller around it do the scrolling: a `TextBox` does
    not scroll itself, so a fixed height would hide the tail of a generated file with no way to
    reach it. Wrapped, because a union type is one very long line and the whole of it has to be
    visible to be trusted -- Ctrl+A copies the real text either way.
]]
function Ui.readOnly(parent: Instance, value: string): TextBox
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromScale(1, 0)
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.BorderSizePixel = 1
    box.ClearTextOnFocus = false
    box.TextEditable = false
    box.MultiLine = true
    box.TextWrapped = true
    box.Font = Enum.Font.Code
    box.TextSize = Ui.TEXT_SIZE
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Text = value

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingTop = UDim.new(0, 4)
    pad.Parent = box

    Theme.paint(box, function()
        box.BackgroundColor3 = Theme.color(COLOR.ScriptBackground)
        box.BorderColor3 = Theme.color(COLOR.InputFieldBorder)
        box.TextColor3 = Theme.color(COLOR.ScriptText)
    end)

    place(box, parent)
    return box
end

--[[
    A whole-width clickable line, indented: the shape a tree row wants.

    Built here rather than in the panel that needs it, so instance construction stays in one
    file and a row picks up the theme like everything else.
]]
function Ui.rowButton(
    parent: Instance,
    indent: number,
    body: string,
    color: Enum.StudioStyleGuideColor,
    onClick: () -> ()
): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, Ui.ROW_HEIGHT)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = ""

    local label = Instance.new("TextLabel")
    label.Position = UDim2.fromOffset(indent, 0)
    label.Size = UDim2.new(1, -indent, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = FONT
    label.TextSize = Ui.TEXT_SIZE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Text = body
    Theme.paint(label, function()
        label.TextColor3 = Theme.color(color)
    end)
    label.Parent = button

    button.Activated:Connect(onClick)
    place(button, parent)
    return button
end

--- A boolean, drawn as a checkbox that says what it means.
function Ui.checkbox(parent: Instance, body: string, value: boolean, onToggle: (boolean) -> ()): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromScale(0, 1)
    button.AutomaticSize = Enum.AutomaticSize.X
    button.Text = (if value then "[x] " else "[ ] ") .. body
    styleButton(button)
    button.Activated:Connect(function()
        onToggle(not value)
    end)
    place(button, parent)
    return button
end

--------------------------------------------------------------------------------
-- The dropdown, and the overlay it needs
--------------------------------------------------------------------------------

--[[
    The frame every menu is drawn into: one per plugin, sized to the whole dock, on top of
    everything. A menu cannot be a child of the button that opened it, because the panels are
    scrollers and it would be clipped by the first one it overflowed.
]]
function Ui.setOverlay(frame: Frame): ()
    overlay = frame
end

--- Names the plugin's GUI for the theme, so painters can be pruned when a panel is destroyed.
function Ui.attach(gui: Instance): ()
    Theme.attach(gui)
end

--- Lets go of Studio. The plugin calls this from `plugin.Unloading`.
function Ui.shutdown(): ()
    Ui.closeMenu()
    Theme.detach()
end

--- Closes any open menu. Panels call it before they redraw, so a menu never outlives its list.
function Ui.closeMenu(): ()
    local host = overlay
    if host ~= nil then
        Ui.clear(host)
        host.Visible = false
    end
end

local function openMenu(anchor: GuiObject, options: { string }, onPick: (string) -> ()): ()
    local host = overlay
    if host == nil or #options == 0 then
        return
    end

    Ui.clear(host)
    host.Visible = true

    local blocker = Instance.new("TextButton")
    blocker.Size = UDim2.fromScale(1, 1)
    blocker.BackgroundTransparency = 1
    blocker.Text = ""
    blocker.ZIndex = MENU_Z
    blocker.Activated:Connect(Ui.closeMenu)
    blocker.Parent = host

    local width = math.max(anchor.AbsoluteSize.X, 140)
    local height = math.min(#options * Ui.ROW_HEIGHT + 2, 220)
    local x = anchor.AbsolutePosition.X - host.AbsolutePosition.X
    local y = anchor.AbsolutePosition.Y - host.AbsolutePosition.Y + anchor.AbsoluteSize.Y

    -- Flip above the anchor rather than run off the bottom of a short dock.
    if y + height > host.AbsoluteSize.Y then
        y = math.max(0, y - anchor.AbsoluteSize.Y - height)
    end

    local menu = Instance.new("ScrollingFrame")
    menu.Position = UDim2.fromOffset(x, y)
    menu.Size = UDim2.fromOffset(width, height)
    menu.CanvasSize = UDim2.new()
    menu.AutomaticCanvasSize = Enum.AutomaticSize.Y
    menu.ScrollBarThickness = 6
    menu.BorderSizePixel = 1
    menu.ZIndex = MENU_Z + 1
    layout(menu, Enum.FillDirection.Vertical, 0)
    Theme.paint(menu, function()
        menu.BackgroundColor3 = Theme.color(COLOR.Dropdown)
        menu.BorderColor3 = Theme.color(COLOR.Border)
        menu.ScrollBarImageColor3 = Theme.color(COLOR.ScrollBar)
    end)
    menu.Parent = host

    for _, option in options do
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, Ui.ROW_HEIGHT)
        item.AutoButtonColor = false
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Font = FONT
        item.TextSize = Ui.TEXT_SIZE
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.TextTruncate = Enum.TextTruncate.AtEnd
        item.Text = option
        item.ZIndex = MENU_Z + 2

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 6)
        pad.Parent = item

        local hovered = false
        local function repaint(): ()
            item.BackgroundTransparency = if hovered then 0 else 1
            item.BackgroundColor3 = Theme.color(COLOR.Button, Enum.StudioStyleGuideModifier.Hover)
            item.TextColor3 = Theme.color(COLOR.MainText)
        end
        Theme.paint(item, repaint)
        item.MouseEnter:Connect(function()
            hovered = true
            repaint()
        end)
        item.MouseLeave:Connect(function()
            hovered = false
            repaint()
        end)

        item.Activated:Connect(function()
            Ui.closeMenu()
            onPick(option)
        end)

        place(item, menu)
    end
end

--[[
    A value picked from a list somebody else computed.

    The plugin never invents an option: roles come from the schemas and from the place, groups
    and widgets from the place, `UnrestBind` from the element's own adapter. `""` is offered as
    "clear it", because removing an attribute has to be as easy as setting one.
]]
function Ui.dropdown(parent: Instance, value: string, options: { string }, onPick: (string) -> ()): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromScale(1, 1)
    button.Text = if value == "" then "(kosong)" else value
    button.TextXAlignment = Enum.TextXAlignment.Left
    button.TextTruncate = Enum.TextTruncate.AtEnd
    styleButton(button)
    button.Activated:Connect(function()
        openMenu(button, options, onPick)
    end)
    place(button, parent)
    return button
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

--- The tab strip. Returns the function that marks one tab current.
function Ui.tabs(parent: Instance, names: { string }, onPick: (index: number) -> ()): (index: number) -> ()
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 26)
    bar.BorderSizePixel = 0
    Theme.paint(bar, function()
        bar.BackgroundColor3 = Theme.color(COLOR.Titlebar)
    end)
    layout(bar, Enum.FillDirection.Horizontal, 0)

    local buttons: { TextButton } = {}
    local current = 1

    local function repaint(): ()
        for index, button in buttons do
            local selected = index == current
            local modifier = if selected
                then Enum.StudioStyleGuideModifier.Selected
                else Enum.StudioStyleGuideModifier.Default
            button.BackgroundColor3 = Theme.color(COLOR.Tab, modifier)
            button.TextColor3 = Theme.color(if selected then COLOR.BrightText else COLOR.SubText)
        end
    end

    for index, name in names do
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromScale(0, 1)
        button.AutomaticSize = Enum.AutomaticSize.X
        button.AutoButtonColor = false
        button.BorderSizePixel = 0
        button.Font = FONT
        button.TextSize = Ui.TEXT_SIZE
        button.Text = name

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.Parent = button

        button.Activated:Connect(function()
            onPick(index)
        end)

        place(button, bar)
        table.insert(buttons, button)
    end

    Theme.paint(bar, repaint)
    bar.Parent = parent

    return function(index: number): ()
        current = index
        repaint()
    end
end

return Ui
