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
    Unrest Plugin / Ui / Theme

    Studio's own palette, and the one place that re-reads it.

    A plugin that hard-codes colours is unreadable in the theme its author does not use, so
    every colour here comes from `settings().Studio.Theme:GetColor`, which is the same table
    Studio paints its own docks with. `ThemeChanged` fires when the user switches, and a
    painter registered here runs again on the spot.

    PAINTERS ARE PRUNED, NOT UNSUBSCRIBED. A painter is remembered with the instance it paints
    and dropped as soon as that instance leaves the plugin's own GUI -- which is exactly what
    happens when a panel is destroyed. That keeps the widget constructors free of teardown
    bookkeeping without leaking a painter per rebuild.
]]

local Theme = {}

type Painter = {
    Instance: Instance,
    Paint: (theme: StudioTheme) -> (),
}

local painters: { Painter } = {}
local root: Instance? = nil
local connection: RBXScriptConnection? = nil

local function studio(): StudioTheme
    return settings().Studio.Theme
end

--- One colour from Studio's palette.
function Theme.color(item: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
    return studio():GetColor(item, modifier)
end

--- Runs `paint` now, and again on every theme change for as long as `instance` is on screen.
function Theme.paint(instance: Instance, paint: (theme: StudioTheme) -> ()): ()
    table.insert(painters, { Instance = instance, Paint = paint })
    paint(studio())
end

--- Repaints everything still mounted, dropping the painters whose instances have gone.
function Theme.apply(): ()
    local theme = studio()
    local anchor = root
    local alive: { Painter } = {}

    for _, painter in painters do
        if anchor ~= nil and not painter.Instance:IsDescendantOf(anchor) then
            continue
        end
        table.insert(alive, painter)
        painter.Paint(theme)
    end

    painters = alive
end

--[[
    Names the plugin's GUI, so a painter can be told from a destroyed one, and connects
    `ThemeChanged` once for the life of the plugin.
]]
function Theme.attach(gui: Instance): ()
    root = gui
    if connection == nil then
        connection = settings().Studio.ThemeChanged:Connect(function()
            Theme.apply()
        end)
    end
end

--- Drops the theme connection. The plugin calls this from `plugin.Unloading`.
function Theme.detach(): ()
    local existing = connection
    if existing ~= nil then
        existing:Disconnect()
        connection = nil
    end
    painters = {}
    root = nil
end

return Theme
