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
    Unrest / Tooling / Lint

    Every rule the Studio tooling checks a screen against, as pure functions returning a list
    of findings. It prints nothing and edits nothing: the plugin draws the list, the Command
    Bar script formats it, and only a `Fix` the caller chooses to run ever touches an
    instance.

    THE SENTENCES ARE COPIED, NOT WRITTEN. Where a rule has a runtime counterpart, the wording
    here is the wording that file `warn`s -- so what the plugin says while the screen is being
    drawn is what the Output window says at Play, word for word, and a designer never has to
    work out that two sentences are the same complaint. `COMMAND_HINT` and the unknown-preset
    sentence are copies of `Elements/init.luau`; the role and duplicate sentences are copies of
    `Widgets/init.luau`; `CommandNotActivatable` goes further and asks `Adapters.rejects` for
    the exact string the runtime would warn.

    A WIDGET ROOT IS EXEMPT FROM THE INTENT RULES. An instance that sets `UnrestWidget` keeps
    its `UnrestCommand` and `UnrestChannel` for the control mounted on it, and `Elements` wires
    neither -- so `CommandNotActivatable`, `ChannelNotBindable` and the command half of
    `IntentOnContainer` would all be complaining about the ordinary shape of a declared slider:
    a Frame, over its parts, saying where its value goes. `Selector.isWidgetRoot` is the
    predicate, and it is the one the runtime skips on, not a copy of it.

    EDIT-MODE SAFE. This module is required by a plugin in a place where nothing is running,
    so it takes its answers from the pure layers only -- `Constants`, `Selector`, `Presets`,
    `Widgets/Schemas` and an `Adapters` registry it builds itself. It must never require
    `Widgets/init` or `Elements/init`: both reach for a running client (`Players.LocalPlayer`,
    the manager's live state) at file scope, and a plugin has neither.

    WHAT EDIT MODE CANNOT SEE. A preset supplies attributes at Play, once the game has called
    `Presets.Register`. Before that the table is empty, so `PresetUnknown` reads the game's
    presets out of the tagged manifests (2.5) -- but every other rule reads attributes through
    `Selector`, which knows only the presets actually registered. In edit mode a preset-supplied
    `UnrestCommand` is therefore invisible to `CommandNotActivatable`, and that is deliberate:
    a second copy of the resolution rule here would drift from the one in `Selector`, and a
    lint that disagrees with the runtime is worse than a lint with a known blind spot.

    NOT IMPLEMENTED: `RoleUnusedInCode` / `RoleMissingInPlace` (proposal 2.4, marked there as
    estimates). Both need a scan of every script's `Source`, which is the `Sources` option, and
    both are guesses until `Vocab` is in use -- a role can be perfectly correct and appear in no
    script at all. `Options.Sources` is accepted so the signature does not change when they
    land.
]]

local CollectionService = game:GetService("CollectionService")

local Adapters = require(script.Parent.Parent.Adapters)
local Constants = require(script.Parent.Parent.Constants)
local Presets = require(script.Parent.Parent.Presets)
local Schemas = require(script.Parent.Parent.Widgets.Schemas)
local Selector = require(script.Parent.Parent.Adapters.Selector)
local Types = require(script.Parent.Parent.Types)
local Vocab = require(script.Parent.Vocab)

local Lint = {}

local ATTRIBUTES = Constants.Attributes

export type Level = "Error" | "Warning" | "Info"

export type Finding = {
    Level: Level,
    --- `"WidgetIncomplete"`, `"RoleWithoutGroup"`, ... The stable half; `Message` is prose.
    Code: string,
    Instance: Instance,
    Message: string,
    --- One edit that fixes it, when there is a safe one. The plugin runs it in ChangeHistory.
    Fix: (() -> ())?,
}

export type Options = {
    --- Check the widget schemas. False skips every rule that needs one. Defaults to true.
    Schemas: boolean?,
    --- Scan script `Source` for the two estimate rules. Not implemented yet; see the header.
    Sources: boolean?,
}

--[[
    Copied verbatim from `Elements/init.luau`, where it is the hint appended to the refusal a
    non-activatable `UnrestCommand` warns with. Copied rather than required because requiring
    `Elements` would drag a running client into a plugin.
]]
local COMMAND_HINT = `Move {Constants.Attributes.Command} onto an element whose class can be activated `
    .. `(a TextButton, ImageButton, ClickDetector or ProximityPrompt), or remove the attribute.`

--- Sort order for the level column. Errors first: they are what stops a screen working.
local LEVEL_ORDER: { [string]: number } = {
    Error = 1,
    Warning = 2,
    Info = 3,
}

--[[
    One registry for the life of the module.

    `Adapters.new()` registers every built-in adapter, and the answers it gives -- `Supports`,
    `CanBind`, `Describe` -- are per-ClassName knowledge with no instance state in them, so
    building one per `check` would re-register the whole table to answer the same questions.
]]
local registry: Types.AdapterRegistry? = nil

local function adapters(): Types.AdapterRegistry
    local existing = registry
    if existing ~= nil then
        return existing
    end
    local built = Adapters.new()
    registry = built
    return built
end

--- The nearest `LayerCollector` at or above `instance`: the screen a name lives on.
local function screenOf(instance: Instance): Instance?
    local current: Instance? = instance
    while current ~= nil and current ~= game do
        local candidate: Instance = current
        if candidate:IsA("LayerCollector") then
            return candidate
        end
        current = candidate.Parent
    end
    return nil
end

--- The nearest instance at or above `instance` that really carries `UnrestIgnore = true`.
local function ignoredBy(instance: Instance): Instance?
    local current: Instance? = instance
    while current ~= nil and current ~= game do
        local candidate: Instance = current
        if candidate:GetAttribute(ATTRIBUTES.Ignore) == true then
            return candidate
        end
        current = candidate.Parent
    end
    return nil
end

--[[
    The instance that carries a group's identity, and so the only instance that can carry its
    `UnrestWidget`.

    Same rule `Widgets` assembles by: an instance that sets its own `UnrestGroup` is its own
    root, and one that inherits the group is rooted at whichever ancestor supplied it.
]]
local function rootOf(instance: Instance): Instance?
    if instance:GetAttribute(ATTRIBUTES.Group) ~= nil then
        return instance
    end
    return Selector.inheritedProviders(instance, { ATTRIBUTES.Group })[ATTRIBUTES.Group]
end

--- A string attribute, or nil when it is absent, empty or of another type.
local function readString(value: any): string?
    if typeof(value) == "string" and #value > 0 then
        return value
    end
    return nil
end

local function sortedList(set: { [string]: boolean }): { string }
    local names: { string } = {}
    for name in set do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--[[
    Every preset name the place declares, and whether anybody declared anything at all.

    Two sources, because there are two moments. At Play the game has already called
    `Presets.Register` and `Presets.List()` is the answer. In edit mode nothing has run, so the
    names come out of the pure-data manifests tagged `UnrestManifest` -- the same tables the
    bootstrap registers, read by a second reader rather than copied for it.

    When neither source has anything, `PresetUnknown` is skipped entirely: a place with no
    manifest has not told the tooling what its presets are, and warning about every one of them
    would be the tooling complaining about its own blindness.
]]
local function declaredPresets(): ({ [string]: boolean }, boolean)
    local known: { [string]: boolean } = {}
    local declared = false

    for _, tagged in CollectionService:GetTagged(Constants.ManifestTag) do
        if not tagged:IsA("ModuleScript") then
            continue
        end
        local ok, manifest = pcall(function()
            return require(tagged) :: any
        end)
        if not ok or typeof(manifest) ~= "table" then
            continue
        end

        declared = true
        local presets = manifest.Presets
        if typeof(presets) == "table" then
            for name in presets do
                if typeof(name) == "string" then
                    known[name] = true
                end
            end
        end
    end

    for _, name in Presets.List() do
        known[name] = true
        declared = true
    end

    return known, declared
end

--- The phrase `Elements` ends its unknown-preset warning with. Copied from `declaredPresets`.
local function presetPhrase(known: { [string]: boolean }): string
    local names = sortedList(known)
    if #names == 0 then
        return "none are declared"
    end
    return table.concat(names, ", ")
end

--- One `Finding` per problem found, ordered Error, Warning, Info and then by instance.
function Lint.check(root: Instance, options: Options?): { Finding }
    local findings: { Finding } = {}
    local useSchemas = if options ~= nil and options.Schemas == false then false else true

    local function report(level: Level, code: string, instance: Instance, message: string, fix: (() -> ())?): ()
        table.insert(findings, { Level = level, Code = code, Instance = instance, Message = message, Fix = fix })
    end

    --[[
        Sorted before anything reads it, so "the first instance that claimed this role" is the
        same instance on every run rather than whatever `GetDescendants` happened to reach
        first. Every rule below that has to pick one of several instances picks this one.
    ]]
    local instances: { Instance } = root:GetDescendants()
    table.insert(instances, root)
    table.sort(instances, function(a: Instance, b: Instance): boolean
        return a:GetFullName() < b:GetFullName()
    end)

    --- Every role any registered schema names. A role outside this set is a game's own word.
    local schemaRoles: { [string]: boolean } = {}
    for _, name in Schemas.List() do
        local schema = Schemas.Get(name)
        if schema ~= nil then
            for _, role in Schemas.Roles(schema) do
                schemaRoles[role] = true
            end
        end
    end

    type Part = { Instance: Instance, Role: string }

    local groupParts: { [string]: { Part } } = {}
    local groupOrder: { string } = {}
    --- First instance seen for each name, and which `Vocab` table the name will land in.
    local firstNamed: { [string]: Instance? } = {}
    local namedIn: { [string]: string } = {}

    local function noteName(name: string, instance: Instance, field: string): ()
        if firstNamed[name] == nil then
            firstNamed[name] = instance
            namedIn[name] = field
        end
    end

    local knownPresets, presetsDeclared = declaredPresets()

    for _, instance in instances do
        --[[
            `UnrestIgnore` is checked on every instance, managed or not, because a Folder that
            carries it is exactly the case the rule is about: the runtime reads only the
            boolean, so a string `"true"` leaves the subtree managed while its author believes
            it is not.
        ]]
        local ignore = instance:GetAttribute(ATTRIBUTES.Ignore)
        if ignore ~= nil and typeof(ignore) ~= "boolean" then
            local literal = tostring(ignore)
            local lowered = string.lower(literal)
            local meant: boolean? = if lowered == "true" then true elseif lowered == "false" then false else nil
            local fix: (() -> ())? = nil
            local remedy = "Replace the attribute with a boolean."
            if meant ~= nil then
                local value: boolean = meant
                fix = function()
                    instance:SetAttribute(ATTRIBUTES.Ignore, value)
                end
                remedy = `Replace the attribute with the boolean {value}.`
            end
            report(
                "Warning",
                "IgnoreNotBoolean",
                instance,
                `[Unrest.Selector] {instance:GetFullName()} sets {ATTRIBUTES.Ignore} = "{literal}" `
                    .. `({typeof(ignore)}), and the framework reads a boolean and nothing looser. The subtree `
                    .. `is still managed. {remedy}`,
                fix
            )
        end

        --- Through `Selector`, not off the instance, because "is this a widget root" is a
        --- question the runtime answers too and one of the two would drift.
        local widget = Selector.widgetOn(instance)
        if widget ~= nil then
            noteName(widget, instance, "Widgets")
        end

        local managed = Selector.isManaged(instance)

        if widget ~= nil and not managed then
            local gate = ignoredBy(instance)
            if gate ~= nil then
                report(
                    "Error",
                    "WidgetRootIgnored",
                    instance,
                    `[Unrest.Widgets] {instance:GetFullName()} sets {ATTRIBUTES.Widget} = "{widget}", but `
                        .. `{ATTRIBUTES.Ignore} on {gate:GetFullName()} opts the subtree out of the `
                        .. `"{Constants.Tag}" tag, so no part under it is managed and the widget is never `
                        .. `assembled.`
                )
            end
        end

        if widget ~= nil and useSchemas and Schemas.Get(widget) == nil then
            local declared = Schemas.List()
            local phrase = if #declared == 0 then "none are declared" else table.concat(declared, ", ")
            report(
                "Warning",
                "WidgetUnknown",
                instance,
                `[Unrest.Widgets] {instance:GetFullName()} sets {ATTRIBUTES.Widget} = "{widget}", which is not a `
                    .. `declared widget schema. Declared schemas: {phrase}. Fix the spelling, or declare it with `
                    .. `Schemas.Register(\{ Name = "{widget}", Required = \{ ... } }).`
            )
        end

        if not managed then
            continue
        end

        local role = Selector.roleOf(instance)
        local group = Selector.groupOf(instance)

        if useSchemas and schemaRoles[role] and group == nil then
            report(
                "Warning",
                "RoleWithoutGroup",
                instance,
                `[Unrest.Widgets] {instance:GetFullName()} plays "{role}" but sets no {Constants.Attributes.Group}, `
                    .. `so there is no widget for it to join.`
            )
        end

        if group ~= nil then
            noteName(group, instance, "Groups")
            local parts = groupParts[group]
            if parts == nil then
                parts = {}
                groupParts[group] = parts
                table.insert(groupOrder, group)
            end
            table.insert(parts, { Instance = instance, Role = role })
        end

        local declaredRole = readString(instance:GetAttribute(ATTRIBUTES.Role))
        if declaredRole ~= nil then
            noteName(declaredRole, instance, "Roles")
        end

        --[[
            `UnrestCommand` on a class with no activation. Asked of `Adapters.rejects`, which is
            the same function the runtime warns through, so the sentence is not a copy of the
            runtime's -- it is the runtime's.

            A widget root is exempt, because `Elements` does not wire its command at all: the
            control `Widgets` mounts there sends it when the gesture settles, and a Frame that
            cannot be activated is the ordinary shape of such a root. Flagging it would be this
            module telling a designer to undo the thing the framework asked them to do.
        ]]
        if widget == nil and readString(instance:GetAttribute(ATTRIBUTES.Command)) ~= nil then
            local refusal = Adapters.rejects(adapters(), instance, {
                Active = function() end,
            }, COMMAND_HINT)
            if refusal ~= nil then
                report("Warning", "CommandNotActivatable", instance, refusal)
            end
        end

        --- Exempt on a widget root for the same reason the command is: the value on that
        --- channel is the control's, and it is painted by moving a knob rather than by
        --- writing a property of the root.
        local channel = if widget == nil then readString((Selector.attributeOf(instance, ATTRIBUTES.Channel))) else nil
        if channel ~= nil then
            local bind = readString((Selector.attributeOf(instance, ATTRIBUTES.Bind)))
            local resolved = adapters():Resolve(instance)
            local property = bind or (if resolved ~= nil then resolved.ValueProperty else nil)

            if property == nil then
                report(
                    "Warning",
                    "ChannelNotBindable",
                    instance,
                    `[Unrest.Elements] {instance:GetFullName()} sets {ATTRIBUTES.Channel} = "{channel}" but there is `
                        .. `nothing to write it into: {adapters():Describe(instance)}. `
                        .. `Add {ATTRIBUTES.Bind} = "<property>".`
                )
            elseif not adapters():CanBind(instance, property) then
                report(
                    "Warning",
                    "ChannelNotBindable",
                    instance,
                    `[Unrest.Elements] {instance:GetFullName()} sets {ATTRIBUTES.Bind} = "{property}", which is not `
                        .. `bindable: {adapters():Describe(instance)}. Bindable is an allowlist, so a channel value `
                        .. `can never write an arbitrary property; register an adapter that permits it if you need it.`
                )
            end
        end

        if presetsDeclared then
            local presetName, source = Selector.attributeOf(instance, ATTRIBUTES.Preset)
            local named = readString(presetName)
            if named ~= nil and not knownPresets[named] then
                local where = if source ~= nil then source.Text else "set here"
                report(
                    "Warning",
                    "PresetUnknown",
                    instance,
                    `[Unrest.Elements] {instance:GetFullName()} resolves {ATTRIBUTES.Preset} = "{named}" `
                        .. `({where}), which is not a declared preset. Declared presets: {presetPhrase(knownPresets)}. `
                        .. `The element was adopted with its own attributes only -- fix the spelling, or declare `
                        .. `it with Presets.Register("{named}", ...).`
                )
            end
        end

        --[[
            Intent sitting on a container.

            A role a schema names is exempt, because that shape is what a widget actually looks
            like: a `SliderTrack` holding a `SliderKnob` is a track with a knob in it, not a
            misplaced attribute. What is left is a word nobody declared, on an instance whose
            children are the things a designer probably meant.

            A command is only suspect on a container the class cannot activate anyway. A
            `TextButton` with an icon `ImageLabel` inside it is the ordinary shape of a button,
            and flagging every one of those would bury the case this rule is for: a `Frame`
            wrapping three buttons, carrying the command one of them was supposed to have.

            A widget root is the deliberate version of exactly that shape -- a Frame with a
            command, over the parts of one control -- so it is exempt as well.
        ]]
        local hasManagedChild = false
        for _, child in instance:GetChildren() do
            if child:IsA("GuiObject") and Selector.isManaged(child) then
                hasManagedChild = true
                break
            end
        end
        if hasManagedChild then
            local misplaced: { string } = {}
            if
                widget == nil
                and readString(instance:GetAttribute(ATTRIBUTES.Command)) ~= nil
                and not adapters():Supports(instance, "Active")
            then
                table.insert(misplaced, ATTRIBUTES.Command)
            end
            if declaredRole ~= nil and not schemaRoles[declaredRole] then
                table.insert(misplaced, ATTRIBUTES.Role)
            end
            if #misplaced > 0 then
                report(
                    "Info",
                    "IntentOnContainer",
                    instance,
                    `[Unrest.Elements] {instance:GetFullName()} sets {table.concat(misplaced, " and ")} and holds `
                        .. `managed GuiObject children. Intent is never inherited -- only `
                        .. `{table.concat(sortedList(Constants.Inheritable :: any), ", ")} are -- so this names the `
                        .. `container itself and reaches none of the parts under it.`
                )
            end
        end
    end

    table.sort(groupOrder)

    for _, group in groupOrder do
        local parts = groupParts[group]

        --[[
            One shared root, or none. A root is a part's own `UnrestGroup` holder, so a group
            whose parts each set their own has as many roots as parts -- and `UnrestWidget`,
            which is never inherited, then has nowhere to sit that covers the whole group.
        ]]
        local shared: Instance? = nil
        local allSelfRooted = true
        for _, part in parts do
            local candidate = rootOf(part.Instance)
            if candidate == nil then
                allSelfRooted = false
                continue
            end

            local holder: Instance = candidate
            if holder ~= part.Instance then
                allSelfRooted = false
            end
            if shared == nil then
                local covers = true
                for _, other in parts do
                    if other.Instance ~= holder and not other.Instance:IsDescendantOf(holder) then
                        covers = false
                        break
                    end
                end
                if covers then
                    shared = holder
                end
            end
        end

        if shared == nil and allSelfRooted and #parts > 1 then
            report(
                "Warning",
                "WidgetNoRoot",
                parts[1].Instance,
                `[Unrest.Widgets] group "{group}" has no shared root: every part sets its own `
                    .. `{ATTRIBUTES.Group}, so it cannot carry {ATTRIBUTES.Widget}.`
            )
        end

        --[[
            Two instances filling one role in one group on one screen. Scoped to the roles a
            schema names, because `roleOf` falls back to `Instance.Name` and two Frames called
            `Frame` under one group is a screen, not a mistake.
        ]]
        local held: { [string]: Instance? } = {}
        for _, part in parts do
            if not schemaRoles[part.Role] then
                continue
            end
            local screen = screenOf(part.Instance)
            -- Keyed by the screen's full name rather than the screen itself, because the
            -- lookup needs a string and two screens can share a `Name`.
            local key = (if screen ~= nil then screen:GetFullName() else "") .. "\0" .. part.Role
            local first = held[key]
            if first == nil then
                held[key] = part.Instance
            else
                report(
                    "Warning",
                    "DuplicateRole",
                    part.Instance,
                    `[Unrest.Widgets] {part.Instance:GetFullName()} also plays "{part.Role}" for group "{group}", which `
                        .. `{first:GetFullName()} already fills. Ignoring the second one -- give it its own `
                        .. `{Constants.Attributes.Group}.`
                )
            end
        end

        --[[
            The same group on two screens. Both `ScreenGui`s are copied into `PlayerGui` at
            Play, so both sets of parts arrive under one group name and the later one is
            dropped part by part -- a duplicate that is invisible until then, because in edit
            mode the two screens look independent.
        ]]
        local screens: { Instance } = {}
        local seenScreen: { [Instance]: boolean } = {}
        for _, part in parts do
            local screen = screenOf(part.Instance)
            if screen ~= nil and not seenScreen[screen] then
                seenScreen[screen] = true
                table.insert(screens, screen)
            end
        end
        if #screens > 1 then
            table.sort(screens, function(a: Instance, b: Instance): boolean
                return a:GetFullName() < b:GetFullName()
            end)
            for index = 2, #screens do
                report(
                    "Warning",
                    "GroupDuplicatedAcrossScreens",
                    screens[index],
                    `[Unrest.Widgets] {screens[index]:GetFullName()} also carries group "{group}", which `
                        .. `{screens[1]:GetFullName()} already fills. At Play both screens reach one PlayerGui and `
                        .. `the second one to arrive is ignored -- give it its own {Constants.Attributes.Group}.`
                )
            end
        end

        if not useSchemas or shared == nil then
            continue
        end

        local widget = readString(shared:GetAttribute(ATTRIBUTES.Widget))
        if widget == nil then
            continue
        end
        local schema = Schemas.Get(widget)
        if schema == nil then
            -- Already reported as `WidgetUnknown`; there is no schema to measure against.
            continue
        end

        local present: { [string]: string } = {}
        local byRole: { [string]: Instance? } = {}
        for _, part in parts do
            if byRole[part.Role] == nil then
                byRole[part.Role] = part.Instance
                present[part.Role] = part.Instance.ClassName
            end
        end

        --[[
            `Schemas.check` compares ClassNames, and only a caller holding instances can answer
            "is a TextButton a GuiButton". This is that caller.
        ]]
        local result = Schemas.check(present, schema, function(role: string, _got: string, expected: string): boolean
            local part = byRole[role]
            return part ~= nil and part:IsA(expected)
        end)

        if #result.Missing > 0 then
            report(
                "Error",
                "WidgetIncomplete",
                shared,
                `[Unrest.Widgets] group "{group}" is not a complete {widget}: `
                    .. `missing {table.concat(result.Missing, ", ")}.`
            )
        end

        if #result.WrongClass > 0 then
            local clauses: { string } = {}
            for _, wrong in result.WrongClass do
                table.insert(clauses, `{wrong.Role} is a {wrong.Got}, needs a {wrong.Expected}`)
            end
            report(
                "Error",
                "WidgetIncomplete",
                shared,
                `[Unrest.Widgets] group "{group}" is not a complete {widget}: ` .. table.concat(clauses, "; ") .. "."
            )
        end
    end

    --[[
        Names `Vocab` will have to write in brackets. Asked of `Vocab.isIdentifier` rather than
        answered again here, so the rule that decides what is awkward and the generator that
        has to cope with it cannot disagree.
    ]]
    local awkward: { [string]: boolean } = {}
    for name in firstNamed do
        if not Vocab.isIdentifier(name) then
            awkward[name] = true
        end
    end
    for _, name in sortedList(awkward) do
        local where = firstNamed[name]
        if where ~= nil then
            report(
                "Info",
                "GroupNotIdentifier",
                where,
                `[Unrest.Tooling] "{name}" is not a Luau identifier, so Vocab writes it as `
                    .. `Vocab.{namedIn[name]}["{name}"] and no editor can autocomplete it. Rename it to `
                    .. `letters, digits and underscores.`
            )
        end
    end

    table.sort(findings, function(a: Finding, b: Finding): boolean
        local left, right = LEVEL_ORDER[a.Level], LEVEL_ORDER[b.Level]
        if left ~= right then
            return left < right
        end
        local leftName, rightName = a.Instance:GetFullName(), b.Instance:GetFullName()
        if leftName ~= rightName then
            return leftName < rightName
        end
        if a.Code ~= b.Code then
            return a.Code < b.Code
        end
        return a.Message < b.Message
    end)

    return findings
end

--- One line per finding, for the Command Bar script and for an agent reading Output over MCP.
function Lint.format(findings: { Finding }): string
    local lines: { string } = {}
    for _, finding in findings do
        table.insert(lines, `[{finding.Level}] {finding.Code} {finding.Instance:GetFullName()}: {finding.Message}`)
    end
    return table.concat(lines, "\n")
end

return Lint
