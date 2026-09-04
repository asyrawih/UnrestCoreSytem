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
    Unrest Plugin / Panels / Inspector

    `Elements.describe` moved into edit mode: what the runtime will conclude about the selected
    instance, before Play is pressed.

    Four answers, in the order somebody debugging asks them. Is this instance managed at all,
    and by what -- its own tag, a cascade from an ancestor, or nothing because an `UnrestIgnore`
    above it cut the subtree off. What can its class do, which is the adapter's own sentence.
    What each `Unrest*` attribute resolves to and *which layer* supplied it, which is the
    three-layer precedence the Properties pane cannot show. And then the editors, which offer
    only values that already exist somewhere -- roles from the schemas and from the place,
    groups from the place, `UnrestBind` from this element's own adapter.

    Every answer is asked of `Selector` and `Adapters` in the open place, so the panel cannot
    disagree with the runtime. Every edit runs inside `context.Record`, so Ctrl+Z takes it back.
]]

local CollectionService = game:GetService("CollectionService")

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Inspector = {}

--- The dropdown entry that removes the attribute. Setting nothing has to be as easy as setting.
local CLEAR = "(kosong — hapus atribut)"

--- Attributes whose value the runtime reads as a number.
local NUMERIC: { [string]: boolean } = { UnrestCooldown = true }

local function sorted(set: { [string]: boolean }): { string }
    local names: { string } = {}
    for name in set do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function Inspector.mount(parent: Frame, framework: Framework.Framework, context: Framework.Context): Framework.Panel
    local Constants = framework.Constants
    local Selector = framework.Selector
    local Adapters = framework.Adapters
    local Presets = framework.Presets
    local Schemas = framework.Schemas

    local scroller = Ui.scroll(parent)
    local watching: { RBXScriptConnection } = {}
    local current: { Instance } = {}
    local alive = true
    local draw: (selection: { Instance }) -> ()

    local function unwatch(): ()
        for _, connection in watching do
            connection:Disconnect()
        end
        watching = {}
    end

    --[[
        A redraw, next frame.

        Never inline: every redraw here is triggered from inside a callback belonging to a
        widget the redraw is about to destroy -- a `TextBox` losing focus, an `AttributeChanged`
        raised by the very `SetAttribute` that fired it. Deferring lets the callback finish
        first, and the flag collapses the burst of `AttributeChanged` a preset edit produces
        into one draw.
    ]]
    local queued = false
    local function redraw(): ()
        if queued or not alive then
            return
        end
        queued = true
        task.defer(function()
            queued = false
            if alive then
                draw(current)
            end
        end)
    end

    --- One edit, recorded, and then a redraw so the source column is right again.
    local function edit(name: string, apply: () -> ()): ()
        context.Record(name, apply)
        redraw()
    end

    --- Every value of `attribute` already typed somewhere under the root. The place's own words.
    local function valuesInPlace(attribute: string): { [string]: boolean }
        local seen: { [string]: boolean } = {}
        for _, descendant in context.Root:GetDescendants() do
            local value = descendant:GetAttribute(attribute)
            if typeof(value) == "string" and #value > 0 then
                seen[value] = true
            end
        end
        return seen
    end

    --- Every role any registered schema names, plus every role the place already uses.
    local function roleOptions(): { string }
        local seen = valuesInPlace(Constants.Attributes.Role)
        if Schemas ~= nil then
            for _, name in Schemas.List() do
                local schema = Schemas.Get(name)
                if schema ~= nil then
                    for _, role in Schemas.Roles(schema) do
                        seen[role] = true
                    end
                end
            end
        end
        return sorted(seen)
    end

    local function withClear(options: { string }): { string }
        local list = { CLEAR }
        table.move(options, 1, #options, 2, list)
        return list
    end

    --- A dropdown that writes `attribute` on `instance`, or clears it.
    local function chooser(slot: Frame, instance: Instance, attribute: string, options: { string }): ()
        local value = instance:GetAttribute(attribute)
        local shown = if typeof(value) == "string" then value else ""
        Ui.dropdown(slot, shown, withClear(options), function(picked: string)
            local next: any = if picked == CLEAR then nil else picked
            edit(`Set {attribute}`, function()
                instance:SetAttribute(attribute, next)
            end)
        end)
    end

    --[[
        A free-text editor.

        Three rules, and each one exists because the alternative silently corrupts data.

        A box that comes back unchanged writes nothing. `FocusLost` fires on every click away,
        not only on an edit, so writing unconditionally would retype `UnrestPayload = 5` as the
        string `"5"` the first time somebody looked at it.

        An empty box *removes* the attribute rather than storing `""`, because the framework
        reads an empty string as absent everywhere and a stored one is a value the Properties
        pane shows and nothing acts on.

        The attribute keeps the type it had. `UnrestCooldown` is always a number -- the runtime
        reads nothing looser -- and a payload that was a number or a boolean stays one. Text
        that will not parse into the type is refused rather than written as a string.
    ]]
    local function writer(slot: Frame, instance: Instance, attribute: string): ()
        local value = instance:GetAttribute(attribute)
        local shown = if value == nil then "" else tostring(value)

        Ui.textBox(slot, shown, function(typed: string)
            if typed == shown then
                return
            end

            local trimmed = string.match(typed, "^%s*(.-)%s*$") or ""
            local next: any = nil

            if trimmed == "" then
                next = nil
            elseif NUMERIC[attribute] or typeof(value) == "number" then
                next = tonumber(trimmed)
                if next == nil then
                    return
                end
            elseif typeof(value) == "boolean" then
                local lowered = string.lower(trimmed)
                if lowered ~= "true" and lowered ~= "false" then
                    return
                end
                next = lowered == "true"
            else
                next = trimmed
            end

            edit(`Set {attribute}`, function()
                instance:SetAttribute(attribute, next)
            end)
        end)
    end

    --[[
        Managed, and by what.

        Read in the order the cascade itself resolves: an `UnrestIgnore` above wins over every
        tag, then the instance's own tag, then the nearest tagged ancestor. `isManaged` is the
        predicate that decides; the walk here only says *why* it answered as it did.
    ]]
    local function managedSentence(instance: Instance): (string, Enum.StudioStyleGuideColor)
        local tag = Constants.Tag
        local ignore = Constants.Attributes.Ignore

        local gate: Instance? = nil
        local tagged: Instance? = nil
        local node: Instance? = instance
        while node ~= nil and node ~= game do
            local candidate: Instance = node
            if gate == nil and candidate:GetAttribute(ignore) == true then
                gate = candidate
            end
            if tagged == nil and CollectionService:HasTag(candidate, tag) then
                tagged = candidate
            end
            node = candidate.Parent
        end

        if gate ~= nil then
            local at: Instance = gate
            local where = if at == instance then "instance ini" else at:GetFullName()
            return `Tidak dikelola: {ignore} = true di {where} mencabut subtree ini dari tag "{tag}".`, Ui.Color.Warning
        end

        if tagged == instance then
            return `Dikelola lewat tag "{tag}" pada instance ini sendiri.`, Ui.Color.Main
        end

        if Selector.isManaged(instance) and tagged ~= nil then
            local root: Instance = tagged
            return `Dikelola lewat cascade dari {root.Name} ({root.ClassName}), yang membawa tag "{tag}".`,
                Ui.Color.Main
        end

        if tagged ~= nil and not instance:IsA("GuiObject") then
            local root: Instance = tagged
            return `Tidak dikelola: {root.Name} bertag "{tag}", tapi cascade hanya menjangkau GuiObject `
                .. `dan {instance.ClassName} bukan salah satunya.`,
                Ui.Color.Dim
        end

        return `Tidak dikelola: tidak ada tag "{tag}" di sini maupun di leluhur mana pun.`, Ui.Color.Dim
    end

    --- The attribute names, ordered the way they read rather than the way a table iterates.
    local function attributeNames(): { string }
        local names: { string } = {}
        for _, name in Constants.Attributes do
            table.insert(names, name)
        end
        table.sort(names)
        return names
    end

    local function drawAttributes(instance: Instance): ()
        local resolution = Selector.resolution(instance)
        local attributes = Constants.Attributes
        local bindable: { string } = {}
        local resolved = Adapters:Resolve(instance)
        if resolved ~= nil then
            for property in resolved.Bindable do
                table.insert(bindable, property)
            end
            table.sort(bindable)
        end

        for _, name in attributeNames() do
            local value, source = Selector.attributeIn(resolution, name)
            local slot = Ui.field(scroller, name)

            if name == attributes.Ignore then
                Ui.checkbox(slot, "UnrestIgnore", value == true, function(next: boolean)
                    edit("Set UnrestIgnore", function()
                        instance:SetAttribute(name, if next then true else nil)
                    end)
                end)
            elseif name == attributes.Role then
                chooser(slot, instance, name, roleOptions())
            elseif name == attributes.Group then
                chooser(slot, instance, name, sorted(valuesInPlace(attributes.Group)))
            elseif name == attributes.Widget then
                chooser(slot, instance, name, if Schemas ~= nil then Schemas.List() else {})
            elseif name == attributes.Preset then
                chooser(slot, instance, name, Presets.List())
            elseif name == attributes.Bind then
                chooser(slot, instance, name, bindable)
            else
                writer(slot, instance, name)
            end

            local shown = if value == nil then "(tidak teresolusi)" else `{tostring(value)}`
            local origin = if source ~= nil then ` — {source.Text}` else ""
            Ui.note(scroller, `  {shown}{origin}`)
        end
    end

    function draw(selection: { Instance }): ()
        current = selection
        unwatch()
        Ui.closeMenu()
        Ui.clear(scroller)

        if #selection == 0 then
            Ui.note(scroller, "Pilih satu instance di Explorer.")
            return
        end

        local instance = selection[1]
        if #selection > 1 then
            Ui.note(scroller, `{#selection} instance dipilih; yang di bawah ini yang pertama.`)
        end

        table.insert(watching, instance.AttributeChanged:Connect(redraw))

        Ui.heading(scroller, `{instance.Name} ({instance.ClassName})`)
        Ui.note(scroller, instance:GetFullName())

        local sentence, color = managedSentence(instance)
        Ui.tinted(scroller, sentence, color)
        Ui.separator(scroller)

        Ui.label(scroller, Adapters:Describe(instance))
        Ui.separator(scroller)

        drawAttributes(instance)
        Ui.separator(scroller)

        local buttons = Ui.row(scroller)
        local tag = Constants.Tag
        if CollectionService:HasTag(instance, tag) then
            Ui.button(buttons, `Lepas tag "{tag}"`, function()
                edit(`Remove {tag} tag`, function()
                    CollectionService:RemoveTag(instance, tag)
                end)
            end)
        else
            Ui.button(buttons, `Tandai "{tag}"`, function()
                edit(`Add {tag} tag`, function()
                    CollectionService:AddTag(instance, tag)
                end)
            end)
        end
    end

    return {
        refresh = draw,
        destroy = function()
            alive = false
            unwatch()
        end,
    }
end

return Inspector
