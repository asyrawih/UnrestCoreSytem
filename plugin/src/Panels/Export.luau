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

    `Tooling/Vocab.generate(StarterGui)`, shown -- and written into the place's own
    `UnrestVocab` module.

    The generator is in the framework, not here, so this panel, `studio/ExportVocab.luau` and an
    agent driving Studio over MCP all produce the same bytes. THE WRITER IS IN THE FRAMEWORK
    TOO: `Vocab.target` finds the module by tag and `Vocab.write` puts the text in it, so this
    file contributes a button, a checkbox and a status line and no rule about where the
    vocabulary lives.

    A PLUGIN STILL HAS NO FILESYSTEM. What it writes is a `ModuleScript.Source` inside the open
    place; the thing that carries it to `src/game-client/Vocab.luau` is the Rojo plugin's
    two-way sync. That is stated in the panel rather than worked around -- with sync off the
    edit is still real, it simply waits in Rojo's Changes viewer. The read-only box stays for
    the same reason it was here before: Studio gives a plugin no clipboard API, so a place that
    has no tagged module at all can still be exported by hand.

    AUTO MODE. The toggle is remembered per install with `plugin:GetSetting`, and while it is on
    the panel regenerates a second after `StarterGui` settles and calls `Vocab.write`. The write
    is a no-op when nothing but the date stamp moved (`Vocab.body`), so an idle place is never
    dirtied and the undo stack collects nothing.
]]

local CollectionService = game:GetService("CollectionService")

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Export = {}

--- Seconds a burst of Studio edits is coalesced over. One instance moved is one signal.
local DEBOUNCE = 1
--- The `plugin:GetSetting` key the auto toggle is remembered under.
local AUTO_SETTING = "UnrestVocabAuto"

local NO_TARGET = "Tidak ada ModuleScript bertag `UnrestVocab` di tempat ini: buat satu di pohon "
    .. "yang di-mount Rojo dan beri tag itu, misalnya lewat `Vocab.meta.json` di sebelah "
    .. "`src/game-client/Vocab.luau`."

local SYNC_NOTE = "Plugin menulis ke ModuleScript di dalam place, bukan ke disk: yang membuatnya "
    .. "mendarat di berkas adalah two-way sync di plugin Rojo. Kalau mati, perubahannya tetap di "
    .. "place dan muncul di penampil Changes milik Rojo."

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

    --[[
        The attributes an edit to which changes the vocabulary, read out of the place's own
        `Constants` -- the plugin spells no attribute name. `UnrestPreset` is in the list
        because a preset can supply `UnrestGroup`, so retyping one moves the groups.
    ]]
    local watched: { [string]: boolean } = {}
    for _, name in
        {
            framework.Constants.Attributes.Role,
            framework.Constants.Attributes.Group,
            framework.Constants.Attributes.Widget,
            framework.Constants.Attributes.Preset,
        }
    do
        watched[name] = true
    end

    --- Signals that live as long as the panel: the shape of the tree, and the tag itself.
    local tree: { RBXScriptConnection } = {}
    --- One `AttributeChanged` per managed descendant. Rebuilt whenever the tree settles.
    local attributes: { RBXScriptConnection } = {}
    local alive = true
    local auto = context.Plugin:GetSetting(AUTO_SETTING) == true
    local generation = 0
    --- The last generated text, and the failure that replaced it. Exactly one is ever set.
    local latest: string? = nil
    local failure: string? = nil
    --- What the last write did, or nil until this session has written something.
    local status: string? = nil

    local render: () -> ()
    local schedule: () -> ()
    local sync: () -> ()

    --[[
        Drops the per-descendant attribute watches and, while auto mode is on, connects a fresh
        set.

        An attribute edit is the common case -- a designer types `UnrestRole` on a button that
        already existed -- and there is no tree-wide signal for one, so it is a connection per
        managed instance. They are rebuilt rather than maintained: the set is only ever wrong
        after the tree changed, and the tree changing is already what schedules this.
    ]]
    local function rewatch(): ()
        for _, connection in attributes do
            connection:Disconnect()
        end
        attributes = {}

        if not auto then
            return
        end

        for _, instance in context.Root:GetDescendants() do
            if not framework.Selector.isManaged(instance) then
                continue
            end
            table.insert(
                attributes,
                instance.AttributeChanged:Connect(function(name: string)
                    if watched[name] then
                        schedule()
                    end
                end)
            )
        end
    end

    local function regenerate(): ()
        local ok, result = pcall(generator.generate, context.Root)
        if ok then
            latest, failure = result, nil
        else
            latest, failure = nil, result
        end
    end

    --[[
        Writes `latest` into the tagged module and records the sentence to show for it.

        Through `context.Record`, so one write is one Ctrl+Z. `Record` swallows a raise into a
        warning, so `wrote` starts nil and staying nil is how a failed write is told apart from
        a write that was not needed.
    ]]
    local function writeNow(): ()
        local text = latest
        if text == nil then
            status = nil
            return
        end

        local target = generator.target()
        if target == nil then
            status = nil
            return
        end

        local wrote: boolean? = nil
        context.Record("Tulis Vocab", function()
            wrote = generator.write(target, text)
        end)

        if wrote == nil then
            status = `Penulisan ke {target:GetFullName()} gagal; lihat Output.`
        elseif wrote then
            status = `{os.date("%H:%M:%S")} — ditulis {#text} bita ke {target:GetFullName()}.`
        else
            status = `{os.date("%H:%M:%S")} — tidak ada perubahan; {target:GetFullName()} sudah mutakhir.`
        end
    end

    function render(): ()
        if not alive then
            return
        end
        Ui.closeMenu()
        Ui.clear(scroller)

        Ui.heading(scroller, "Vocab.luau")
        Ui.note(scroller, `Dihasilkan dari {context.Root:GetFullName()}.`)
        Ui.tinted(scroller, SYNC_NOTE, Ui.Color.Info)

        local target = generator.target()
        if target == nil then
            Ui.tinted(scroller, NO_TARGET, Ui.Color.Warning)
            Ui.tinted(
                scroller,
                "Sementara itu: klik di dalam kotak, Ctrl+A, Ctrl+C — Studio tidak punya API papan "
                    .. "klip untuk plugin.",
                Ui.Color.Info
            )
        else
            Ui.note(scroller, `Sasaran: {target:GetFullName()}`)
        end

        local buttons = Ui.row(scroller)
        Ui.button(buttons, "Segarkan", function()
            task.defer(function()
                regenerate()
                render()
            end)
        end)
        -- Deferred: the write yields, and the redraw destroys the button we are still inside.
        Ui.button(buttons, "Tulis ke Vocab", function()
            task.defer(function()
                regenerate()
                writeNow()
                render()
            end)
        end)

        Ui.checkbox(scroller, "Otomatis — tulis ulang saat StarterGui berubah", auto, function(value: boolean)
            auto = value
            context.Plugin:SetSetting(AUTO_SETTING, value)
            task.defer(function()
                rewatch()
                render()
                if auto then
                    schedule()
                end
            end)
        end)

        local last = status
        if last ~= nil then
            Ui.note(scroller, last)
        end
        Ui.separator(scroller)

        local text, gagal = latest, failure
        if gagal ~= nil then
            Ui.tinted(scroller, `Vocab gagal: {gagal}`, Ui.Color.Error)
            return
        end
        if text ~= nil then
            Ui.readOnly(scroller, text)
        end
    end

    --[[
        One settled burst of edits: re-aim the attribute watches, regenerate, and write when
        auto mode says so.

        The panel is redrawn only when the text or the status actually moved, so an edit
        somewhere in `StarterGui` that the vocabulary does not care about leaves the box the
        reader is looking at alone.
    ]]
    function sync(): ()
        if not alive then
            return
        end
        rewatch()

        local before, previous = latest, status
        regenerate()
        if auto then
            writeNow()
        end

        if latest ~= before or status ~= previous then
            render()
        end
    end

    --- Coalesces a burst of edits into one sync. Studio fires one signal per instance moved.
    function schedule(): ()
        generation += 1
        local token = generation
        task.delay(DEBOUNCE, function()
            if alive and token == generation then
                sync()
            end
        end)
    end

    table.insert(tree, context.Root.DescendantAdded:Connect(schedule))
    table.insert(tree, context.Root.DescendantRemoving:Connect(schedule))
    --[[
        Tagging an instance that already existed is the whole opt-in, and it is neither a
        descendant change nor an attribute change -- without these two, giving a Frame the
        `Unrest` tag would leave the vocabulary a screen behind.
    ]]
    table.insert(tree, CollectionService:GetInstanceAddedSignal(framework.Constants.Tag):Connect(schedule))
    table.insert(tree, CollectionService:GetInstanceRemovedSignal(framework.Constants.Tag):Connect(schedule))

    rewatch()
    regenerate()
    render()

    return {
        refresh = function(_selection: { Instance }) end,
        destroy = function()
            alive = false
            for _, connection in tree do
                connection:Disconnect()
            end
            tree = {}
            for _, connection in attributes do
                connection:Disconnect()
            end
            attributes = {}
        end,
    }
end

return Export
