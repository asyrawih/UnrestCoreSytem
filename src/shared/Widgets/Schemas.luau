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

--[[
    Unrest / Widgets / Schemas

    What a widget is made of, as data. A schema names the roles a widget needs, the roles it
    may also have, and the class each role must at least be. Three readers share it, and that
    is the whole reason it is a table rather than a list inside a control:

      * the runtime, to assemble a group and to say in `Widgets:Report()` why one is not
        assembled yet;
      * the Studio tooling (`Tooling/Lint`, the plugin), to flag an incomplete widget while
        it is being drawn, in edit mode, with no framework running;
      * the vocabulary generator, to turn roles into typed constants.

    PURE. This module requires no service and touches no Instance, so it can be required
    from a plugin in edit mode and exercised in plain Luau. `check` works on role -> class
    name tables; the caller decides what "is a" means, because only the caller has instances.

    THE FRAMEWORK SHIPS THREE. Slider, Progress and Toggle are the controls the framework
    itself knows how to drive. A game registers its own with `Schemas.Register`, exactly as it
    registers presets, and nothing here needs to know what went in.

    ROLES ARE SPELLED IN FULL. `SliderTrack`, never `Track`. A role is identity across the
    whole screen, and a short one namespaced by its widget is a second identity mechanism
    in disguise.
]]

export type WidgetSchema = {
    Name: string,
    Required: { string },
    Optional: { string }?,
    --- Minimum class per role, tested with `:IsA()` by callers that hold instances.
    Classes: { [string]: string }?,
}

export type WrongClass = { Role: string, Expected: string, Got: string }

export type SchemaCheck = {
    --- Required roles nobody plays.
    Missing: { string },
    --- Roles played that the schema does not name.
    Extra: { string },
    --- Roles played by an instance of the wrong class.
    WrongClass: { WrongClass },
}

--- How a caller answers "is `got` at least an `expected`". Defaults to exact equality.
export type IsA = (role: string, got: string, expected: string) -> boolean

local SCHEMAS: { [string]: WidgetSchema } = {}

local Schemas = {}

local function sameClass(_role: string, got: string, expected: string): boolean
    return got == expected
end

--- The schema named `name`, or nil when nobody registered one.
function Schemas.Get(name: string): WidgetSchema?
    return SCHEMAS[name]
end

--- Registered schema names, sorted, for error messages and tooling.
function Schemas.List(): { string }
    local names: { string } = {}
    for name in SCHEMAS do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Every role a schema names, required first, in declaration order.
function Schemas.Roles(schema: WidgetSchema): { string }
    local roles = table.clone(schema.Required)
    if schema.Optional ~= nil then
        for _, role in schema.Optional do
            table.insert(roles, role)
        end
    end
    return roles
end

--[[
    Registers a schema, replacing one of the same name. Replacement is intentional for the
    same reason it is in `Presets`: a game that wants "Slider" to mean something else says so
    in one place. Validation is strict because a schema is read by tooling that cannot ask
    questions: a role listed twice or a class for a role nobody plays is a typo, and a typo
    in a schema is wrong on every screen at once.
]]
function Schemas.Register(schema: WidgetSchema): WidgetSchema
    if typeof(schema) ~= "table" then
        error(`[Unrest.Widgets.Schemas] Register expects a schema table, got {typeof(schema)}.`, 0)
    end
    local name = schema.Name
    if typeof(name) ~= "string" or name == "" then
        error("[Unrest.Widgets.Schemas] Register expects a schema with a non-empty Name.", 0)
    end
    if typeof(schema.Required) ~= "table" or #schema.Required == 0 then
        error(`[Unrest.Widgets.Schemas] schema "{name}" needs at least one Required role.`, 0)
    end

    local seen: { [string]: boolean } = {}
    for _, role in Schemas.Roles(schema) do
        if typeof(role) ~= "string" or role == "" then
            error(`[Unrest.Widgets.Schemas] schema "{name}" lists a role that is not a non-empty string.`, 0)
        end
        if seen[role] then
            error(`[Unrest.Widgets.Schemas] schema "{name}" lists the role "{role}" twice.`, 0)
        end
        seen[role] = true
    end

    if schema.Classes ~= nil then
        for role, className in schema.Classes do
            if not seen[role] then
                error(
                    `[Unrest.Widgets.Schemas] schema "{name}" gives a class for "{role}", which is not one of its roles.`,
                    0
                )
            end
            if typeof(className) ~= "string" or className == "" then
                error(`[Unrest.Widgets.Schemas] schema "{name}" gives "{role}" a class that is not a string.`, 0)
            end
        end
    end

    SCHEMAS[name] = schema
    return schema
end

--[[
    Compares the roles a group plays against a schema. `present` maps each role played to
    the ClassName playing it. `isA` decides class compatibility; a caller with instances
    passes one built on `Instance:IsA`, a test passes nothing and gets exact matching.

    Every list comes back sorted so two calls over the same input render the same text.
]]
function Schemas.check(present: { [string]: string }, schema: WidgetSchema, isA: IsA?): SchemaCheck
    local compatible: IsA = isA or sameClass
    local known: { [string]: boolean } = {}
    local missing: { string } = {}
    local extra: { string } = {}
    local wrong: { WrongClass } = {}

    for _, role in schema.Required do
        known[role] = true
        if present[role] == nil then
            table.insert(missing, role)
        end
    end
    if schema.Optional ~= nil then
        for _, role in schema.Optional do
            known[role] = true
        end
    end

    for role, className in present do
        if not known[role] then
            table.insert(extra, role)
            continue
        end
        local expected = if schema.Classes ~= nil then schema.Classes[role] else nil
        if expected ~= nil and not compatible(role, className, expected) then
            table.insert(wrong, { Role = role, Expected = expected, Got = className })
        end
    end

    table.sort(missing)
    table.sort(extra)
    table.sort(wrong, function(a, b)
        return a.Role < b.Role
    end)

    return { Missing = missing, Extra = extra, WrongClass = wrong }
end

--- Whether `check` found nothing to say.
function Schemas.complete(result: SchemaCheck): boolean
    return #result.Missing == 0 and #result.WrongClass == 0
end

--[[
    The three the framework drives. Derived from the controls in `game-client/Example`, with
    one deliberate loosening: a Slider needs only a track and a knob. A fill or a label that
    is absent is a slider that does not show one, not a broken slider.
]]
Schemas.Register({
    Name = "Slider",
    Required = { "SliderTrack", "SliderKnob" },
    Optional = { "SliderFill", "SliderLabel" },
    Classes = { SliderTrack = "GuiObject", SliderKnob = "GuiObject" },
})

Schemas.Register({
    Name = "Progress",
    Required = { "SliderTrack", "SliderFill" },
    Optional = { "SliderLabel" },
    Classes = { SliderTrack = "GuiObject", SliderFill = "GuiObject" },
})

Schemas.Register({
    Name = "Toggle",
    Required = { "ToggleButton", "ToggleKnob" },
    Optional = { "ToggleLabel" },
    Classes = { ToggleButton = "GuiButton", ToggleKnob = "GuiObject" },
})

return Schemas
