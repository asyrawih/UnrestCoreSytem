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
    Unrest Plugin

    A Properties pane that knows the framework. It shows what the runtime will conclude about
    the instances in `StarterGui` -- managed or not, which adapter, what each `Unrest*`
    attribute resolves to and from which layer, which widgets are incomplete -- before Play is
    pressed.

    IT BUILDS NO UI AND IT CARRIES NO RULE. There is no "make me a slider" button: the seed
    scripts in `studio/` are still the only thing that creates instances, and this plugin edits
    the ones a designer already drew. Every rule it draws is required out of the open place
    (`Framework.luau`), so the panel and the runtime cannot drift: adding a rule to
    `src/shared/Tooling/Lint.luau` makes it appear here with no plugin release, and there is no
    second copy of the attribute list, the cascade or the schemas anywhere under `plugin/`.

    NEVER MOUNTED IN THE PLACE. `plugin/default.project.json` is its own Rojo project, built to
    a `.rbxm` and installed into Studio (`scripts/install-plugin.sh`). Like `bench/`, it is never
    added to `default.project.json`.

    ---------------------------------------------------------------------------------------
    THE PANEL CONTRACT
    ---------------------------------------------------------------------------------------

    Every module under `Panels/` exports exactly one function:

        mount(parent: Frame, framework: Framework.Framework, context: Framework.Context) -> Panel

    and the `Panel` it returns is two functions:

        refresh(selection: { Instance })  -- redraw from scratch; the selection changed, or the
                                             host switched to this tab
        destroy()                         -- drop every connection the panel owns

    The rules the contract exists to enforce:

      * A panel never keeps state across a `refresh`. It clears its frame and draws it again,
        which is why nothing here can go stale and why there is no invalidation to get wrong.
      * A panel never edits an instance directly. Every edit goes through `context.Record`, so
        one click is one Ctrl+Z, and `context.Select` is the only way to move the selection.
      * A panel never destroys `parent`. The host owns the frame; the panel owns its
        connections, and `destroy` is about those.
      * A panel whose framework module is missing (`framework.Lint == nil` on an older release)
        mounts anyway and draws one sentence. Degrade, never fail.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local Export = require(script.Panels.Export)
local Framework = require(script.Framework)
local Inspector = require(script.Panels.Inspector)
local Outline = require(script.Panels.Outline)
local Problems = require(script.Panels.Problems)
local Ui = require(script.Ui)
local WidgetsPanel = require(script.Panels.Widgets)

--[[
    A `.rbxm` dropped into the wrong place -- `ServerScriptService`, say -- runs as an ordinary
    Script with no `plugin` global. Leave rather than throw: the mistake is the install, and a
    stack trace in the Output window of somebody's game says nothing useful about it.
]]
if not plugin then
    return
end

local TAB_HEIGHT = 26

local TABS: { { Name: string, Module: Framework.PanelModule } } = {
    { Name = "Inspector", Module = Inspector },
    { Name = "Outline", Module = Outline },
    { Name = "Problems", Module = Problems },
    { Name = "Widgets", Module = WidgetsPanel },
    { Name = "Export", Module = Export },
}

local toolbar = plugin:CreateToolbar("Unrest")
local button = toolbar:CreateButton("UnrestPanel", "Kelola tag dan atribut Unrest di StarterGui", "", "Unrest")
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
    "UnrestPanel",
    DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 480, 300, 320)
)
widget.Name = "UnrestPanel"
widget.Title = "Unrest"
--[[
    Global, not Sibling: the dropdown menus are drawn into an overlay that is a sibling of the
    panels, and only a flat comparison puts them above a panel's own scroller.
]]
widget.ZIndexBehavior = Enum.ZIndexBehavior.Global

Ui.attach(widget)

local root = Ui.panel(widget)
root.Visible = true

--[[
    One edit, one undo entry.

    `TryBeginRecording` returns nil when a recording is already open -- Studio allows one at a
    time -- and the edit still has to happen, so the nil case is not an early return. A failed
    edit cancels its recording rather than committing half of one.
]]
local function record(name: string, apply: () -> ()): ()
    local recording = ChangeHistoryService:TryBeginRecording(name)
    local ok, err = pcall(function(): any?
        apply()
        return nil
    end)

    if recording ~= nil then
        ChangeHistoryService:FinishRecording(
            recording,
            if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
        )
    end

    if not ok then
        warn(`[UnrestPlugin] {name} gagal: {err}`)
    end
end

local context: Framework.Context = {
    Root = StarterGui,
    Plugin = plugin,
    Record = record,
    Select = function(instances: { Instance })
        Selection:Set(instances)
    end,
}

local panels: { Framework.Panel } = {}
local frames: { Frame } = {}
local watchers: { RBXScriptConnection } = {}
local active = 1
local build: () -> ()

local function teardown(): ()
    for _, connection in watchers do
        connection:Disconnect()
    end
    watchers = {}

    for _, panel in panels do
        panel.destroy()
    end
    panels = {}
    frames = {}

    Ui.closeMenu()
    Ui.clear(root)
end

function build(): ()
    teardown()

    local framework = Framework.find()
    if framework == nil then
        local empty = Ui.scroll(root)
        Ui.heading(empty, "Unrest")
        Ui.note(empty, Framework.explain())
        Ui.button(Ui.row(empty), "Muat ulang", build)
        return
    end

    local found: Framework.Framework = framework

    local content = Instance.new("Frame")
    content.Position = UDim2.fromOffset(0, TAB_HEIGHT)
    content.Size = UDim2.new(1, 0, 1, -TAB_HEIGHT)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.Parent = root

    local names: { string } = {}
    for _, tab in TABS do
        table.insert(names, tab.Name)
    end

    local show: (index: number) -> ()
    local setActive = Ui.tabs(root, names, function(index: number)
        show(index)
    end)

    --[[
        One panel raising must not take the dock with it. Everything after this loop --
        `show`, the selection watcher -- is what makes the tabs work, so a `mount` that raised
        here used to leave a tab bar whose every click called nothing. The failed panel gets
        its error where its content would be, and the rest of the dock carries on.
    ]]
    for _, tab in TABS do
        local frame = Ui.panel(content)
        table.insert(frames, frame)
        local ok, panel = pcall(tab.Module.mount, frame, found, context)
        if ok then
            table.insert(panels, panel)
        else
            local message = tostring(panel)
            warn(`[UnrestPlugin] panel {tab.Name} gagal dipasang: {message}`)
            local note = Ui.scroll(frame)
            Ui.heading(note, tab.Name)
            Ui.tinted(note, `Panel ini gagal dipasang: {message}`, Ui.Color.Warning)
            table.insert(panels, {
                refresh = function() end,
                destroy = function() end,
            })
        end
    end

    --[[
        The overlay is created last and lives above `content`, because a menu opened from a row
        inside a scroller would otherwise be clipped by the scroller that owns the row.
    ]]
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundTransparency = 1
    overlay.BorderSizePixel = 0
    overlay.Visible = false
    overlay.ZIndex = 40
    overlay.Parent = root
    Ui.setOverlay(overlay)

    function show(index: number): ()
        active = index
        Ui.closeMenu()
        for position, frame in frames do
            frame.Visible = position == index
        end
        setActive(index)
        panels[index].refresh(Selection:Get())
    end

    table.insert(
        watchers,
        Selection.SelectionChanged:Connect(function()
            local panel = panels[active]
            if panel ~= nil then
                panel.refresh(Selection:Get())
            end
        end)
    )

    local version = found.Version
    if found.Outdated then
        warn(
            `[UnrestPlugin] framework {version} lebih tua dari {Framework.MinimumVersion}; `
                .. "sebagian panel mungkin kosong."
        )
    end

    show(1)
end

local function open(): ()
    if #panels == 0 then
        build()
    end
end

button.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
    button:SetActive(widget.Enabled)
    if widget.Enabled then
        open()
    end
end)

plugin.Unloading:Connect(function()
    teardown()
    Ui.shutdown()
end)

button:SetActive(widget.Enabled)
if widget.Enabled then
    open()
end
