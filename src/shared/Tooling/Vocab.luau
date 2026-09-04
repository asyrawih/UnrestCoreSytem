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
    Unrest / Tooling / Vocab

    Turns the vocabulary a place already speaks -- its roles, its groups, its widgets -- into
    a typed Luau module, so `Vocab.Roles.SliderKnob` autocompletes and
    `Vocab.Roles.SilderKnob` is a `--!strict` error instead of a query that silently matches
    nothing.

    Three doors call this one function: the Command Bar script `studio/ExportVocab.luau`, an
    agent session over MCP running that same script, and (later) the plugin's Export panel.
    The generator lives in the framework rather than in any of them so that all three emit
    the same bytes.

    PURE ENOUGH TO TEST. `render` never touches an Instance: it takes a `Vocabulary` and a
    date stamp and returns a string, sorted throughout, so calling it twice on the same input
    gives the same file. `collect` is the only half that reads the tree, and it reads it
    through `Selector` -- the same rule the runtime matches on.

    CHANNELS AND COMMANDS ARE NOT GENERATED, on purpose. Only part of them is ever written in
    an attribute (code publishes `Volume.Musik` without any attribute saying so), and an
    incomplete union would make `--!strict` reject correct code. Channel names belong to the
    game and are typed by the game.
]]

local Constants = require(script.Parent.Parent.Constants)
local Selector = require(script.Parent.Parent.Adapters.Selector)

local Vocab = {}

--- Each name in the place, mapped to the instance paths that use it.
export type Vocabulary = {
    Roles: { [string]: { string } },
    Groups: { [string]: { string } },
    Widgets: { [string]: { string } },
}

local INDENT = "    "
--- The column width `stylua.toml` enforces; a union longer than this is wrapped like stylua wraps it.
local STYLUA_WIDTH = 120

--- Luau keywords, which are spelled like identifiers but cannot be one.
local KEYWORDS: { [string]: boolean } = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

--[[
    Whether `name` can be written as a bare table key, `Vocab.Roles.SliderKnob`, rather than
    as `Vocab.Roles["Slider Knob"]`.

    Exported because `Tooling/Lint` reports the awkward ones (`GroupNotIdentifier`) and the
    two must agree about which names are awkward. One answer, one place.
]]
function Vocab.isIdentifier(name: string): boolean
    if KEYWORDS[name] then
        return false
    end
    return string.match(name, "^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

--- `name` as a Luau string literal.
local function quote(name: string): string
    local escaped = string.gsub(name, "\\", "\\\\")
    escaped = string.gsub(escaped, '"', '\\"')
    return '"' .. escaped .. '"'
end

--[[
    Where an instance sits, written from the nearest `LayerCollector` down:
    `SliderMulti.Musik.Track (Frame)`.

    The screen is the widest scope a name means anything in -- `ancestorChain` stops there for
    exactly the same reason -- and a path that started at `game` would be three words of noise
    before the part anybody reads.
]]
local function pathOf(instance: Instance): string
    local names: { string } = { instance.Name }

    if not instance:IsA("LayerCollector") then
        local current: Instance? = instance.Parent
        while current ~= nil and current ~= game do
            local ancestor: Instance = current
            table.insert(names, 1, ancestor.Name)
            if ancestor:IsA("LayerCollector") then
                break
            end
            current = ancestor.Parent
        end
    end

    return table.concat(names, ".") .. ` ({instance.ClassName})`
end

local function record(into: { [string]: { string } }, name: string, path: string): ()
    local paths = into[name]
    if paths == nil then
        paths = {}
        into[name] = paths
    end
    table.insert(paths, path)
end

--[[
    Reads the vocabulary out of a subtree. Only instances the framework manages count: an
    untagged decorative Frame named `SliderKnob` is not vocabulary, it is a Frame.

    ROLES ARE READ FROM THE ATTRIBUTE ONLY, never from `Instance.Name`. `Selector.roleOf`
    falls back to the name so that a button called `ToggleMenu` keeps working without an
    attribute, and that fallback is right for *matching* -- but a name is not vocabulary
    until somebody declares it. Generating a union out of every managed instance's name would
    put `Frame`, `TextLabel_3` and `UICorner` in `Vocab.Roles`, and the misspelling this file
    exists to catch would be buried in it.

    Groups do resolve through inheritance, because a group written once on a ScreenGui is a
    group every element under it really is in.
]]
function Vocab.collect(root: Instance): Vocabulary
    local vocabulary: Vocabulary = { Roles = {}, Groups = {}, Widgets = {} }

    local instances: { Instance } = root:GetDescendants()
    table.insert(instances, root)

    for _, instance in instances do
        if not Selector.isManaged(instance) then
            continue
        end

        local path = pathOf(instance)

        local role = instance:GetAttribute(Constants.Attributes.Role)
        if typeof(role) == "string" and #role > 0 then
            record(vocabulary.Roles, role, path)
        end

        local group = Selector.groupOf(instance)
        if group ~= nil then
            record(vocabulary.Groups, group, path)
        end

        local widget = instance:GetAttribute(Constants.Attributes.Widget)
        if typeof(widget) == "string" and #widget > 0 then
            record(vocabulary.Widgets, widget, path)
        end
    end

    for _, paths in vocabulary.Roles do
        table.sort(paths)
    end
    for _, paths in vocabulary.Groups do
        table.sort(paths)
    end
    for _, paths in vocabulary.Widgets do
        table.sort(paths)
    end

    return vocabulary
end

local function sortedKeys(entries: { [string]: { string } }): { string }
    local names: { string } = {}
    for name in entries do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

type Section = {
    --- The field on the generated table: `Roles`.
    Field: string,
    --- The exported union: `Role`.
    TypeName: string,
    --- The attribute an empty section is empty of, for the comment that explains the widening.
    Attribute: string,
    Entries: { [string]: { string } },
}

--[[
    The generated file, as text.

    Deterministic by construction: every key is walked in sorted order and every path list
    was sorted by `collect`, so two runs over an unchanged place produce identical bytes and
    the diff of a re-export shows only what actually changed on the screen.

    An empty section widens to `string` rather than collapsing to `never`. A place with no
    `UnrestWidget` anywhere has not declared that widgets are impossible; a `never` there
    would reject every literal a developer writes next, which is the opposite of the help
    this file is for.
]]
function Vocab.render(vocabulary: Vocabulary, stamp: string): string
    local sections: { Section } = {
        { Field = "Roles", TypeName = "Role", Attribute = Constants.Attributes.Role, Entries = vocabulary.Roles },
        { Field = "Groups", TypeName = "Group", Attribute = Constants.Attributes.Group, Entries = vocabulary.Groups },
        {
            Field = "Widgets",
            TypeName = "Widget",
            Attribute = Constants.Attributes.Widget,
            Entries = vocabulary.Widgets,
        },
    }

    local lines: { string } = {
        "--!strict",
        `-- DIHASILKAN oleh Tooling/Vocab dari StarterGui pada {stamp}. Jangan disunting; ekspor ulang.`,
        "",
    }

    for _, section in sections do
        local names = sortedKeys(section.Entries)
        if #names == 0 then
            table.insert(
                lines,
                `--- Tempat ini tidak menyetel satu pun {section.Attribute}, jadi tipenya dibiarkan lebar.`
            )
            table.insert(lines, `export type {section.TypeName} = string`)
            continue
        end

        local union: { string } = {}
        for _, name in names do
            table.insert(union, quote(name))
        end
        --[[
            Written the way stylua would format it, so the generated file passes
            `stylua --check` untouched: one line while it fits the 120-column width, otherwise
            one member per line with the bar leading. A generator that emits what the
            formatter would rewrite is a generator whose output is never clean.
        ]]
        local oneLine = `export type {section.TypeName} = ` .. table.concat(union, " | ")
        if #oneLine <= STYLUA_WIDTH then
            table.insert(lines, oneLine)
        else
            table.insert(lines, `export type {section.TypeName} =`)
            table.insert(lines, `{INDENT}{union[1]}`)
            for index = 2, #union do
                table.insert(lines, `{INDENT}| {union[index]}`)
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, "local Vocab = {")

    for _, section in sections do
        local names = sortedKeys(section.Entries)
        if #names == 0 then
            table.insert(lines, `{INDENT}{section.Field} = table.freeze(` .. "{}),")
            continue
        end

        table.insert(lines, `{INDENT}{section.Field} = table.freeze(` .. "{")
        for _, name in names do
            local paths = section.Entries[name]
            if #paths > 0 then
                table.insert(lines, `{INDENT}{INDENT}--- ` .. table.concat(paths, ", "))
            end

            local literal = quote(name)
            local key = if Vocab.isIdentifier(name) then name else `[{literal}]`
            table.insert(lines, `{INDENT}{INDENT}{key} = {literal} :: {literal},`)
        end
        table.insert(lines, `{INDENT}` .. "}),")
    end

    table.insert(lines, "}")
    table.insert(lines, "")
    table.insert(lines, "return table.freeze(Vocab)")

    return table.concat(lines, "\n") .. "\n"
end

--- `collect` then `render`, stamped with today's date. The whole door, for the three callers.
function Vocab.generate(root: Instance): string
    return Vocab.render(Vocab.collect(root), os.date("%Y-%m-%d"))
end

return Vocab
