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
    Unrest Plugin / Panels / Problems

    `Tooling/Lint`, drawn.

    THE PLUGIN OWNS NO RULE HERE. Every finding, its level, its wording and its fix come out of
    `src/shared/Tooling/Lint.luau`; this file contributes a list, a colour per level and a
    button. That is the point of the split: the sentence a designer reads in edit mode is the
    sentence the Output window prints at Play, because it is literally the same string, and a
    rule added to `Lint` appears here with no plugin release.

    A `Fix` is run inside `context.Record`, so a one-click repair is one Ctrl+Z.

    RESCANNING. `Lint.check` reads the whole of `StarterGui`, so it is not something to run per
    keystroke. It runs on mount, on demand, and otherwise behind a half-second debounce fed by
    the selection and by `DescendantAdded` / `DescendantRemoving` -- which is what makes deleting
    an `UnrestRole` show up as a finding about a second later without a poll.
]]

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Problems = {}

local DEBOUNCE = 0.5

local LEVEL_COLOR: { [string]: Enum.StudioStyleGuideColor } = {
    Error = Ui.Color.Error,
    Warning = Ui.Color.Warning,
    Info = Ui.Color.Info,
}

function Problems.mount(parent: Frame, framework: Framework.Framework, context: Framework.Context): Framework.Panel
    local scroller = Ui.scroll(parent)
    local connections: { RBXScriptConnection } = {}
    local generation = 0
    local alive = true

    local Lint = framework.Lint
    local render: () -> ()

    if Lint == nil then
        Ui.note(scroller, Framework.needs("Tooling/Lint"))
        return {
            refresh = function() end,
            destroy = function() end,
        }
    end

    local rules = Lint

    local function drawFinding(finding: any): ()
        local color = LEVEL_COLOR[finding.Level] or Ui.Color.Main
        local instance: Instance = finding.Instance

        Ui.rowButton(scroller, 0, `[{finding.Level}] {finding.Code} — {instance.Name}`, color, function()
            context.Select({ instance })
        end)
        Ui.note(scroller, finding.Message)

        local fix = finding.Fix
        if fix ~= nil then
            local buttons = Ui.row(scroller)
            -- Deferred: the redraw destroys the button whose click we are still inside.
            Ui.button(buttons, "Perbaiki", function()
                context.Record(`Fix {finding.Code}`, fix)
                task.defer(render)
            end)
        end
        Ui.separator(scroller)
    end

    function render(): ()
        if not alive then
            return
        end
        Ui.closeMenu()
        Ui.clear(scroller)

        local ok, findings = pcall(rules.check, context.Root)
        if not ok then
            Ui.tinted(scroller, `Lint gagal: {findings}`, Ui.Color.Error)
            return
        end

        local counts = { Error = 0, Warning = 0, Info = 0 }
        for _, finding in findings do
            counts[finding.Level] += 1
        end

        Ui.heading(
            scroller,
            `{#findings} temuan — {counts.Error} Error, {counts.Warning} Warning, {counts.Info} Info`
        )
        Ui.note(scroller, `Dipindai: {context.Root:GetFullName()}`)

        local buttons = Ui.row(scroller)
        Ui.button(buttons, "Periksa ulang", function()
            task.defer(render)
        end)
        Ui.separator(scroller)

        if #findings == 0 then
            Ui.tinted(scroller, "Bersih. Tidak ada aturan yang dilanggar layar ini.", Ui.Color.Info)
            return
        end

        for _, finding in findings do
            drawFinding(finding)
        end
    end

    --- Coalesces a burst of edits into one scan. Studio fires one signal per instance moved.
    local function schedule(): ()
        generation += 1
        local token = generation
        task.delay(DEBOUNCE, function()
            if alive and token == generation then
                render()
            end
        end)
    end

    table.insert(connections, context.Root.DescendantAdded:Connect(schedule))
    table.insert(connections, context.Root.DescendantRemoving:Connect(schedule))

    render()

    return {
        refresh = function(_selection: { Instance })
            schedule()
        end,
        destroy = function()
            alive = false
            for _, connection in connections do
                connection:Disconnect()
            end
            connections = {}
        end,
    }
end

return Problems
