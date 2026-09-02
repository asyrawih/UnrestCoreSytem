--!strict
--[[
    Unrest / Bridge / Resolver

    The whiteboard's "Typed Check Lua Resolver".

    Luau's type checker only protects callers that are themselves typed. Query descriptors
    and handler tables are the framework's public boundary, so every one of them is also
    checked at runtime against a schema, and a bad table fails immediately with a message
    that names the offending key, says what was expected, what arrived, and shows a fix --
    including a "did you mean" suggestion for near-miss key names.

    Validators return the *same* table, narrowed to its public type, so call sites read as
    `local descriptor = Resolver.Descriptor(input)`.
]]

local Types = require(script.Parent.Parent.Types)

local Resolver = {}

type FieldSpec = {
    --- Result of `typeof()` the field must have.
    Kind: string,
    --- Appended to the error message so it explains itself.
    Hint: string,
}

type Schema = { [string]: FieldSpec }

local DESCRIPTOR_SCHEMA: Schema = {
    Tag = { Kind = "string", Hint = 'a CollectionService tag, e.g. Tag = "Unrest"' },
    Selector = { Kind = "string", Hint = 'a ClassName tested with :IsA(), e.g. Selector = "TextButton"' },
    Name = { Kind = "string", Hint = 'an exact Instance.Name, e.g. Name = "ToggleMenu"' },
    Ancestor = { Kind = "Instance", Hint = "the Instance to search under when no Tag is given" },
    Recursive = { Kind = "boolean", Hint = "search all descendants of Ancestor (defaults to true)" },
}

local HANDLER_SCHEMA: Schema = {
    Active = { Kind = "function", Hint = "Activated / MouseClick / Triggered, e.g. Active = function(element) end" },
    Hover = { Kind = "function", Hint = "MouseEnter, e.g. Hover = function(element) end" },
    Unhover = { Kind = "function", Hint = "MouseLeave, e.g. Unhover = function(element) end" },
    Added = { Kind = "function", Hint = "an element started matching, e.g. Added = function(element) end" },
    Removed = { Kind = "function", Hint = "an element stopped matching, e.g. Removed = function(element) end" },
}

local SYSTEM_SCHEMA: Schema = {
    Name = { Kind = "string", Hint = 'the unique registry key, e.g. Name = "MusicSystem"' },
    Dependencies = { Kind = "table", Hint = 'an array of system names, e.g. Dependencies = { "AvatarContext" }' },
    Init = { Kind = "function", Hint = "Init = function(self, unrest) end" },
    Start = { Kind = "function", Hint = "Start = function(self) end" },
    Destroy = { Kind = "function", Hint = "Destroy = function(self) end" },
}

local COMPONENT_SCHEMA: Schema = {
    Name = { Kind = "string", Hint = 'the unique component key, e.g. Name = "DxChipsX"' },
    Create = { Kind = "function", Hint = "Create = function(props, bridge): ComponentHandle" },
}

--------------------------------------------------------------------------------
-- Message helpers
--------------------------------------------------------------------------------

local function fail(message: string): never
    error("[Unrest.Resolver] " .. message, 0)
end

local function sortedKeys(schema: Schema): string
    local keys: { string } = {}
    for key in schema do
        table.insert(keys, key)
    end
    table.sort(keys)
    return table.concat(keys, ", ")
end

--- Short, safe rendering of an arbitrary value for an error message.
local function describe(value: any): string
    local kind = typeof(value)
    local rendered = tostring(value)
    if #rendered > 48 then
        rendered = string.sub(rendered, 1, 45) .. "..."
    end
    if kind == "string" then
        return `string ("{rendered}")`
    end
    return `{kind} ({rendered})`
end

--- Classic Levenshtein distance, used only to suggest the key the caller probably meant.
local function distance(a: string, b: string): number
    local lengthA, lengthB = #a, #b
    if lengthA == 0 then
        return lengthB
    end

    local previous: { number } = table.create(lengthA + 1, 0)
    local current: { number } = table.create(lengthA + 1, 0)
    for index = 0, lengthA do
        previous[index + 1] = index
    end

    for indexB = 1, lengthB do
        current[1] = indexB
        local charB = string.sub(b, indexB, indexB)
        for indexA = 1, lengthA do
            local cost = if string.sub(a, indexA, indexA) == charB then 0 else 1
            current[indexA + 1] = math.min(current[indexA] + 1, previous[indexA + 1] + 1, previous[indexA] + cost)
        end
        previous, current = current, previous
    end

    return previous[lengthA + 1]
end

local function suggest(key: string, schema: Schema): string?
    local bestKey: string? = nil
    local bestScore = math.huge
    local lowered = string.lower(key)

    for candidate in schema do
        local score = distance(lowered, string.lower(candidate))
        if score < bestScore then
            bestScore, bestKey = score, candidate
        end
    end

    -- Only volunteer a suggestion when it is genuinely close.
    if bestKey ~= nil and bestScore <= math.max(2, math.floor(#key / 3)) then
        return bestKey
    end
    return nil
end

--[[
    Validates every key/value pair of `value` against `schema`.
    `strict` rejects keys the schema does not know about; systems set it to false because a
    system table legitimately carries its own private state alongside the lifecycle fields.
]]
local function check(value: any, schema: Schema, label: string, strict: boolean): ()
    if typeof(value) ~= "table" then
        fail(`{label} must be a table, got {describe(value)}. Valid fields: {sortedKeys(schema)}.`)
    end

    for key, field in value :: { [any]: any } do
        if typeof(key) ~= "string" then
            fail(`{label} keys must be strings, got a {typeof(key)} key. Valid fields: {sortedKeys(schema)}.`)
        end

        local spec = schema[key :: string]
        if spec == nil then
            if not strict then
                continue
            end
            local guess = suggest(key :: string, schema)
            local hint = if guess ~= nil then ` Did you mean "{guess}"?` else ""
            fail(`unknown {label} field "{key}".{hint} Valid fields: {sortedKeys(schema)}.`)
        elseif typeof(field) ~= spec.Kind then
            fail(`{label} field "{key}" expects a {spec.Kind} ({spec.Hint}) but got {describe(field)}.`)
        end
    end
end

--------------------------------------------------------------------------------
-- Public validators
--------------------------------------------------------------------------------

--- Validates a Query descriptor and returns it typed.
function Resolver.Descriptor(value: any): Types.Descriptor
    check(value, DESCRIPTOR_SCHEMA, "Query descriptor", true)

    local descriptor = value :: Types.Descriptor
    if descriptor.Tag == nil and descriptor.Selector == nil and descriptor.Name == nil then
        fail(
            "Query descriptor needs at least one of Tag, Selector or Name -- "
                .. 'e.g. { Tag = "Unrest", Selector = "TextButton", Name = "ToggleMenu" }.'
        )
    end
    if descriptor.Tag == nil and descriptor.Ancestor == nil then
        fail(
            "Query descriptor without a Tag must supply an Ancestor to search under -- "
                .. 'e.g. { Selector = "TextButton", Ancestor = playerGui }. '
                .. "A tagless, rootless query would have to scan the whole DataModel."
        )
    end
    if descriptor.Tag ~= nil and #descriptor.Tag == 0 then
        fail('Query descriptor field "Tag" must not be an empty string.')
    end
    if descriptor.Selector ~= nil and #descriptor.Selector == 0 then
        fail('Query descriptor field "Selector" must not be an empty string.')
    end

    return descriptor
end

--- Validates a handler table and returns it typed.
function Resolver.Handlers(value: any): Types.Handlers
    check(value, HANDLER_SCHEMA, "Query handler", true)
    return value :: Types.Handlers
end

--- Validates a system definition. Unknown keys are allowed: systems carry their own state.
function Resolver.System(value: any): Types.System
    check(value, SYSTEM_SCHEMA, "System definition", false)

    local system = value :: Types.System
    if typeof(system.Name) ~= "string" or #system.Name == 0 then
        fail('System definition requires a non-empty string Name, e.g. Name = "MusicSystem".')
    end

    local dependencies = system.Dependencies
    if dependencies ~= nil then
        for index, dependency in dependencies do
            if typeof(dependency) ~= "string" then
                fail(
                    `System "{system.Name}" has a non-string Dependencies[{index}]: {describe(dependency)}. `
                        .. "Dependencies is an array of system names."
                )
            end
        end
    end

    return system
end

--- Validates a UI component definition.
function Resolver.Component(value: any): Types.Component
    check(value, COMPONENT_SCHEMA, "Component definition", false)

    local component = value :: Types.Component
    if typeof(component.Name) ~= "string" or #component.Name == 0 then
        fail('Component definition requires a non-empty string Name, e.g. Name = "DxChipsX".')
    end
    if typeof(component.Create) ~= "function" then
        fail(`Component "{component.Name}" requires a Create(props, bridge) function.`)
    end

    return component
end

return Resolver
