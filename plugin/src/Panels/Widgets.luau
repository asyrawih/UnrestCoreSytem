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
    Unrest Plugin / Panels / Widgets

    One table per `UnrestGroup`: what the group has, what its schema says it needs, and the two
    edits that close the gap.

    The comparison is `Schemas.check`, the same function `Widgets:Report()` calls at runtime, so
    a group this panel calls complete is a group that assembles at Play. The panel supplies the
    one thing `check` cannot: instances. `check` compares class *names* because it is pure, so
    the `isA` it is handed here answers with `Instance:IsA` -- which is why a `TextButton` counts
    as the `GuiObject` a slider knob must be.

    A GROUP'S ROOT IS NOT A NEW RULE. It is the nearest instance that supplies the group's
    `UnrestGroup`, which is `Selector.inheritedProviders`, and it is the only instance that may
    carry the group's `UnrestWidget`. The same two lines are in `Tooling/Lint.luau:153`; they are
    derived from `Selector` in both places rather than owned by either.
]]

local Framework = require(script.Parent.Parent.Framework)
local Ui = require(script.Parent.Parent.Ui)

local Widgets = {}

type Part = { Instance: Instance, Role: string }

--- The deepest instance every one of `instances` sits at or under.
local function commonAncestor(instances: { Instance }): Instance?
    if #instances == 0 then
        return nil
    end

    local chain: { Instance } = {}
    local node: Instance? = instances[1]
    while node ~= nil and node ~= game do
        local candidate: Instance = node
        table.insert(chain, candidate)
        node = candidate.Parent
    end

    for _, candidate in chain do
        local covers = true
        for _, instance in instances do
            if instance ~= candidate and not instance:IsDescendantOf(candidate) then
                covers = false
                break
            end
        end
        if covers then
            return candidate
        end
    end

    return nil
end

--- Whether an instance is somewhere a `UnrestGroup` can be read from: a screen, or inside one.
local function insideScreen(instance: Instance): boolean
    local node: Instance? = instance
    while node ~= nil and node ~= game do
        local candidate: Instance = node
        if candidate:IsA("LayerCollector") then
            return true
        end
        node = candidate.Parent
    end
    return false
end

function Widgets.mount(parent: Frame, framework: Framework.Framework, context: Framework.Context): Framework.Panel
    local Constants = framework.Constants
    local Selector = framework.Selector
    local Schemas = framework.Schemas

    local attributes = Constants.Attributes
    local scroller = Ui.scroll(parent)
    local current: { Instance } = {}
    local draw: (selection: { Instance }) -> ()

    if Schemas == nil then
        Ui.note(scroller, Framework.needs("Widgets/Schemas"))
        return {
            refresh = function() end,
            destroy = function() end,
        }
    end

    local schemas = Schemas

    --- Deferred, because the redraw destroys the dropdown or button that asked for the edit.
    local function edit(name: string, apply: () -> ()): ()
        context.Record(name, apply)
        task.defer(function()
            draw(current)
        end)
    end

    --- The instance carrying this group's identity. See the header: derived, never owned here.
    local function rootOf(instance: Instance): Instance?
        if instance:GetAttribute(attributes.Group) ~= nil then
            return instance
        end
        return Selector.inheritedProviders(instance, { attributes.Group })[attributes.Group]
    end

    --- Every managed instance under the root that resolves a group, bucketed by that group.
    local function collect(): ({ [string]: { Part } }, { string })
        local groups: { [string]: { Part } } = {}
        local order: { string } = {}

        local instances = context.Root:GetDescendants()
        table.sort(instances, function(a: Instance, b: Instance): boolean
            return a:GetFullName() < b:GetFullName()
        end)

        for _, instance in instances do
            if not Selector.isManaged(instance) then
                continue
            end
            local group = Selector.groupOf(instance)
            if group == nil then
                continue
            end
            if groups[group] == nil then
                groups[group] = {}
                table.insert(order, group)
            end
            table.insert(groups[group], { Instance = instance, Role = Selector.roleOf(instance) })
        end

        table.sort(order)
        return groups, order
    end

    --- Every role any registered schema names, for the "make this the X" dropdown.
    local function allRoles(): { string }
        local seen: { [string]: boolean } = {}
        for _, name in schemas.List() do
            local schema = schemas.Get(name)
            if schema ~= nil then
                for _, role in schemas.Roles(schema) do
                    seen[role] = true
                end
            end
        end
        local roles: { string } = {}
        for role in seen do
            table.insert(roles, role)
        end
        table.sort(roles)
        return roles
    end

    local function drawGroup(group: string, parts: { Part }): ()
        Ui.heading(scroller, `Grup "{group}" — {#parts} bagian`)

        --- First instance per role, and every later claimant, which is what a duplicate is.
        local first: { [string]: Instance? } = {}
        local duplicates: { Part } = {}
        for _, part in parts do
            if first[part.Role] == nil then
                first[part.Role] = part.Instance
            else
                table.insert(duplicates, part)
            end
        end

        local rootSet: { [Instance]: boolean } = {}
        local rootList: { Instance } = {}
        for _, part in parts do
            local root = rootOf(part.Instance)
            if root ~= nil and not rootSet[root] then
                rootSet[root] = true
                table.insert(rootList, root)
            end
        end

        local root: Instance? = if #rootList == 1 then rootList[1] else nil
        if root ~= nil then
            local at: Instance = root
            Ui.note(scroller, `Akar: {at:GetFullName()}`)
        else
            Ui.tinted(
                scroller,
                `Tanpa akar bersama: {#rootList} instance menyetel {attributes.Group} sendiri-sendiri, `
                    .. `jadi tidak ada satu instance pun yang boleh membawa {attributes.Widget}.`,
                Ui.Color.Warning
            )
        end

        local widget: string? = nil
        if root ~= nil then
            local declared = root:GetAttribute(attributes.Widget)
            if typeof(declared) == "string" and #declared > 0 then
                widget = declared
            end
        end

        local roles: { string } = {}
        for role in first do
            table.insert(roles, role)
        end
        table.sort(roles)
        Ui.note(scroller, `Peran: {table.concat(roles, ", ")}`)

        if widget == nil then
            Ui.note(scroller, `Tidak ada {attributes.Widget} di akar; tidak ada skema untuk dibandingkan.`)
        else
            local name: string = widget
            local schema = schemas.Get(name)
            if schema == nil then
                Ui.tinted(
                    scroller,
                    `{attributes.Widget} = "{name}" tidak dikenal. Yang terdaftar: {table.concat(schemas.List(), ", ")}.`,
                    Ui.Color.Warning
                )
            else
                local present: { [string]: string } = {}
                for role, instance in first do
                    if instance ~= nil then
                        present[role] = instance.ClassName
                    end
                end

                local result = schemas.check(present, schema, function(role: string, _got: string, expected: string)
                    local instance = first[role]
                    return instance ~= nil and instance:IsA(expected)
                end)

                if schemas.complete(result) and #duplicates == 0 then
                    Ui.tinted(scroller, `Widget "{name}" lengkap.`, Ui.Color.Info)
                end
                if #result.Missing > 0 then
                    Ui.tinted(scroller, `Kurang: {table.concat(result.Missing, ", ")}`, Ui.Color.Error)
                end
                if #result.Extra > 0 then
                    Ui.note(scroller, `Di luar skema: {table.concat(result.Extra, ", ")}`)
                end
                for _, wrong in result.WrongClass do
                    Ui.tinted(
                        scroller,
                        `Salah kelas: {wrong.Role} harus {wrong.Expected}, tapi {wrong.Got}.`,
                        Ui.Color.Error
                    )
                end
            end
        end

        for _, part in duplicates do
            local kept = first[part.Role]
            if kept == nil then
                continue
            end
            Ui.tinted(
                scroller,
                `Peran ganda: {part.Instance:GetFullName()} juga mengaku "{part.Role}"; `
                    .. `{kept:GetFullName()} yang dipakai.`,
                Ui.Color.Warning
            )
        end

        local actions = Ui.row(scroller)

        local slot = Instance.new("Frame")
        slot.Size = UDim2.new(0, 220, 1, 0)
        slot.BackgroundTransparency = 1
        slot.BorderSizePixel = 0
        slot.LayoutOrder = #actions:GetChildren()
        slot.Parent = actions

        local schemaRoles = allRoles()
        if widget ~= nil then
            local schema = schemas.Get(widget)
            if schema ~= nil then
                schemaRoles = schemas.Roles(schema)
            end
        end

        Ui.dropdown(slot, "", schemaRoles, function(role: string)
            if #current == 0 then
                return
            end
            local selection = current
            edit(`Set {attributes.Role}`, function()
                for _, instance in selection do
                    instance:SetAttribute(attributes.Role, role)
                end
            end)
        end)
        Ui.note(scroller, `  ^ jadikan seleksi ({#current} instance) peran yang dipilih`)

        if root == nil and #rootList > 1 then
            local ancestor = commonAncestor(rootList)
            if ancestor ~= nil and insideScreen(ancestor) then
                local target: Instance = ancestor
                Ui.button(actions, `Pindahkan {attributes.Group} ke {target.Name}`, function()
                    local owners = rootList
                    edit(`Move {attributes.Group} to {target.Name}`, function()
                        target:SetAttribute(attributes.Group, group)
                        for _, owner in owners do
                            if owner ~= target then
                                owner:SetAttribute(attributes.Group, nil)
                            end
                        end
                    end)
                end)
            else
                Ui.note(scroller, "Tidak ada induk bersama di dalam satu ScreenGui; pindahkan bagiannya dulu.")
            end
        end

        Ui.separator(scroller)
    end

    function draw(selection: { Instance }): ()
        current = selection
        Ui.closeMenu()
        Ui.clear(scroller)

        local groups, order = collect()
        if #order == 0 then
            Ui.note(
                scroller,
                `Tidak ada instance dikelola yang meresolusi {attributes.Group} di bawah {context.Root.Name}.`
            )
            return
        end

        for _, group in order do
            drawGroup(group, groups[group])
        end
    end

    return {
        refresh = draw,
        destroy = function()
            Ui.clear(scroller)
        end,
    }
end

return Widgets
