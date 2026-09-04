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
    Unrest Plugin / Panels / Outline

    The managed tree, which is not the Explorer tree.

    Explorer shows what is in the place. This shows what the framework will adopt: every tagged
    root under `StarterGui` and everything its cascade reaches, grouped by the screen it is on.
    The two differ in both directions -- a `UIListLayout` under a tagged Frame is in Explorer
    and not here, and an `UnrestIgnore` subtree is here, dimmed, precisely because a designer
    needs to see the hole it cut.

    The enumeration is `Selector.cascadeUnder`, the same function `Elements` adopts with, so a
    row drawn here is an element the runtime will adopt and a row that is missing is one it will
    not. The badges are `Selector.roleOf` and the resolved attributes, so what a row says about
    a group is what a query on that group will match.
]]

local CollectionService = game:GetService("CollectionService")

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Outline = {}

local INDENT = 14

--- The nearest `LayerCollector` at or above `instance`: the screen a row belongs under.
local function screenOf(instance: Instance): Instance?
    local node: Instance? = instance
    while node ~= nil and node ~= game do
        local candidate: Instance = node
        if candidate:IsA("LayerCollector") then
            return candidate
        end
        node = candidate.Parent
    end
    return nil
end

function Outline.mount(parent: Frame, framework: Framework.Framework, context: Framework.Context): Framework.Panel
    local Constants = framework.Constants
    local Selector = framework.Selector

    local attributes = Constants.Attributes
    local wiring = { attributes.Command, attributes.Payload, attributes.Channel, attributes.Bind, attributes.Format }

    local scroller = Ui.scroll(parent)
    local filter = ""
    local draw: (selection: { Instance }) -> ()

    --[[
        The badges after a row's name: what the runtime will know about it.

        A role is shown only when the attribute is set, because `roleOf` falls back to the
        instance name and printing "role=Frame" on every undecorated Frame would be noise. A
        group carries an arrow when it was inherited rather than typed here, which is the one
        thing about a group that surprises people.
    ]]
    local function badgesFor(instance: Instance): string
        local parts: { string } = {}

        local role = instance:GetAttribute(attributes.Role)
        if typeof(role) == "string" and #role > 0 then
            table.insert(parts, `role={role}`)
        end

        local resolution = Selector.resolution(instance)
        local group, groupSource = Selector.attributeIn(resolution, attributes.Group)
        if typeof(group) == "string" and #group > 0 then
            local inherited = if groupSource ~= nil and groupSource.Origin ~= "Own" then " ^" else ""
            table.insert(parts, `group={group}{inherited}`)
        end

        local widget = instance:GetAttribute(attributes.Widget)
        if typeof(widget) == "string" and #widget > 0 then
            table.insert(parts, `widget={widget}`)
        end

        local preset, presetSource = Selector.attributeIn(resolution, attributes.Preset)
        if typeof(preset) == "string" and #preset > 0 then
            local inherited = if presetSource ~= nil and presetSource.Origin ~= "Own" then " ^" else ""
            table.insert(parts, `preset={preset}{inherited}`)
        end

        for _, name in wiring do
            if instance:GetAttribute(name) ~= nil then
                table.insert(parts, (string.gsub(name, "^Unrest", "")))
            end
        end

        if #parts == 0 then
            return ""
        end
        return "  ·  " .. table.concat(parts, "  ")
    end

    local function matches(instance: Instance): boolean
        if filter == "" then
            return true
        end
        local needle = string.lower(filter)
        local hay = string.lower(`{instance.Name} {instance.ClassName} {badgesFor(instance)}`)
        return string.find(hay, needle, 1, true) ~= nil
    end

    --- One clickable line. Clicking it puts the instance in Studio's selection.
    local function row(instance: Instance, depth: number, dimmed: boolean, suffix: string): ()
        Ui.rowButton(
            scroller,
            depth * INDENT,
            `{instance.Name} ({instance.ClassName}){suffix}{badgesFor(instance)}`,
            if dimmed then Ui.Color.Dim else Ui.Color.Main,
            function()
                context.Select({ instance })
            end
        )
    end

    --[[
        The cascade under one tagged root, drawn.

        `cascadeUnder` has already decided which instances are managed; this walk only decides
        where they sit, so the indentation never claims a parentage the enumeration disagrees
        with. Depth advances only on a drawn row, which is what makes a Folder between two
        Frames invisible rather than an empty level.
    ]]
    local function drawCascade(root: Instance): ()
        local managed = Selector.cascadeUnder(root)
        local isManaged: { [Instance]: boolean } = {}
        for _, instance in managed do
            isManaged[instance] = true
        end

        local function walk(node: Instance, depth: number): ()
            for _, child in node:GetChildren() do
                if child:GetAttribute(attributes.Ignore) == true then
                    local pruned = #child:GetDescendants()
                    row(child, depth, true, ` — {attributes.Ignore}, {pruned} keturunan dilewati`)
                    continue
                end
                if isManaged[child] then
                    row(child, depth, false, "")
                    walk(child, depth + 1)
                else
                    walk(child, depth)
                end
            end
        end

        row(root, 0, false, ` — akar bertag`)
        walk(root, 1)
    end

    --- Every tagged root under the panel's root, sorted so two draws read the same.
    local function roots(): { Instance }
        local found: { Instance } = {}
        for _, tagged in CollectionService:GetTagged(Constants.Tag) do
            if tagged:IsDescendantOf(context.Root) then
                table.insert(found, tagged)
            end
        end
        table.sort(found, function(a: Instance, b: Instance): boolean
            return a:GetFullName() < b:GetFullName()
        end)
        return found
    end

    --- A tagged root inside another tagged root is already drawn by the outer one's cascade.
    local function isNested(root: Instance, all: { Instance }): boolean
        for _, other in all do
            if other ~= root and root:IsDescendantOf(other) then
                return true
            end
        end
        return false
    end

    --[[
        With a filter typed, the tree becomes a flat list of hits.

        Indentation is a claim about ancestry, and a filtered tree either shows ancestors that
        do not match -- which is not a filter -- or draws children under parents that are not
        there. A path per row says the same thing without lying about it.
    ]]
    local function drawMatches(): ()
        local count = 0
        for _, root in roots() do
            local candidates: { Instance } = { root }
            local managed = Selector.cascadeUnder(root)
            table.move(managed, 1, #managed, 2, candidates)

            for _, instance in candidates do
                if matches(instance) then
                    count += 1
                    row(instance, 0, false, "")
                    Ui.note(scroller, `    {instance:GetFullName()}`)
                end
            end
        end
        if count == 0 then
            Ui.note(scroller, `Tidak ada yang cocok dengan "{filter}".`)
        end
    end

    function draw(_selection: { Instance }): ()
        Ui.closeMenu()
        Ui.clear(scroller)

        -- Deferred: this callback belongs to the TextBox the redraw is about to destroy.
        Ui.textBox(Ui.field(scroller, "Filter"), filter, function(typed: string)
            if typed == filter then
                return
            end
            filter = typed
            task.defer(draw, _selection)
        end)

        local all = roots()
        if #all == 0 then
            Ui.note(scroller, `Tidak ada instance bertag "{Constants.Tag}" di bawah {context.Root.Name}.`)
            return
        end

        if filter ~= "" then
            drawMatches()
            return
        end

        local screens: { Instance } = {}
        local byScreen: { [Instance]: { Instance } } = {}
        local loose: { Instance } = {}

        for _, root in all do
            if isNested(root, all) then
                continue
            end
            local screen = screenOf(root)
            if screen == nil then
                table.insert(loose, root)
                continue
            end
            local key: Instance = screen
            if byScreen[key] == nil then
                byScreen[key] = {}
                table.insert(screens, key)
            end
            table.insert(byScreen[key], root)
        end

        for _, screen in screens do
            Ui.heading(scroller, `{screen.Name} ({screen.ClassName})`)
            for _, root in byScreen[screen] do
                drawCascade(root)
            end
            Ui.separator(scroller)
        end

        if #loose > 0 then
            Ui.heading(scroller, "Di luar ScreenGui")
            for _, root in loose do
                drawCascade(root)
            end
        end
    end

    return {
        refresh = draw,
        destroy = function()
            Ui.clear(scroller)
        end,
    }
end

return Outline
