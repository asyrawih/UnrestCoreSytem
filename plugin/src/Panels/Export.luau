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
    Unrest Plugin / Panels / Export

    `Tooling/Vocab.generate(StarterGui)`, shown so it can be copied into
    `src/game-client/Vocab.luau`.

    The generator is in the framework, not here, so this panel, `studio/ExportVocab.luau` and an
    agent driving Studio over MCP all print the same bytes. Two of those three can write the
    file; this one cannot, because a Studio plugin has no filesystem access and no clipboard
    API. That is stated in the panel rather than worked around: a "Salin" button that silently
    did nothing would be worse than a box that says select-all and copy.
]]

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Export = {}

function Export.mount(parent: Frame, framework: Framework.Framework, context: Framework.Context): Framework.Panel
    local scroller = Ui.scroll(parent)
    local Vocab = framework.Vocab

    if Vocab == nil then
        Ui.note(scroller, Framework.needs("Tooling/Vocab"))
        return {
            refresh = function() end,
            destroy = function() end,
        }
    end

    local generator = Vocab
    local render: () -> ()

    function render(): ()
        Ui.closeMenu()
        Ui.clear(scroller)

        Ui.heading(scroller, "Vocab.luau")
        Ui.note(
            scroller,
            "Dihasilkan dari "
                .. context.Root:GetFullName()
                .. ". Salin isinya apa adanya ke "
                .. "src/game-client/Vocab.luau; jangan disunting tangan, ekspor ulang."
        )
        Ui.tinted(
            scroller,
            "Studio tidak punya API papan klip untuk plugin: klik di dalam kotak, Ctrl+A, Ctrl+C.",
            Ui.Color.Info
        )

        local buttons = Ui.row(scroller)
        Ui.button(buttons, "Segarkan", function()
            task.defer(render)
        end)

        local ok, source = pcall(generator.generate, context.Root)
        if not ok then
            Ui.tinted(scroller, `Vocab gagal: {source}`, Ui.Color.Error)
            return
        end

        Ui.readOnly(scroller, source)
    end

    render()

    return {
        refresh = function(_selection: { Instance }) end,
        destroy = function()
            Ui.clear(scroller)
        end,
    }
end

return Export
