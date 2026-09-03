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
    Unrest / Util / Resolver

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
    Role = { Kind = "string", Hint = 'the UnrestRole attribute, e.g. Role = "ToggleMenu"' },
    Group = { Kind = "string", Hint = 'the UnrestGroup attribute, e.g. Group = "MainMenu"' },
    Ancestor = { Kind = "Instance", Hint = "the Instance to search under when no Tag is given" },
    Recursive = { Kind = "boolean", Hint = "search all descendants of Ancestor (defaults to true)" },
}

--[[
    The handler matrix, in the order a pointer travels: enter, press, release, activate,
    leave. Whether a given element *supports* one of these is the adapter's business and is
    answered at bind time; the Resolver only checks that the table is shaped like a handler
    table at all.
]]
local HANDLER_SCHEMA: Schema = {
    Active = { Kind = "function", Hint = "Activated / MouseClick / Triggered, e.g. Active = function(element) end" },
    Secondary = { Kind = "function", Hint = "MouseButton2Click, e.g. Secondary = function(element) end" },
    Press = { Kind = "function", Hint = "pointer down, e.g. Press = function(element) end" },
    Release = { Kind = "function", Hint = "pointer up, e.g. Release = function(element) end" },
    Hover = { Kind = "function", Hint = "MouseEnter, e.g. Hover = function(element) end" },
    Unhover = { Kind = "function", Hint = "MouseLeave, e.g. Unhover = function(element) end" },
    Focus = { Kind = "function", Hint = "TextBox gained focus, e.g. Focus = function(element) end" },
    Blur = { Kind = "function", Hint = "TextBox lost focus, e.g. Blur = function(element) end" },
    Submit = { Kind = "function", Hint = "TextBox committed with Enter, e.g. Submit = function(element, text) end" },
    Changed = { Kind = "function", Hint = "the value property changed, e.g. Changed = function(element, value) end" },
    Added = { Kind = "function", Hint = "an element started matching, e.g. Added = function(element) end" },
    Removed = { Kind = "function", Hint = "an element stopped matching, e.g. Removed = function(element) end" },
}

local SYSTEM_SCHEMA: Schema = {
    Name = { Kind = "string", Hint = 'the unique registry key, e.g. Name = "MySystem"' },
    Dependencies = { Kind = "table", Hint = 'an array of system names, e.g. Dependencies = { "MyOtherSystem" }' },
    Init = { Kind = "function", Hint = "Init = function(self, unrest) end" },
    Start = { Kind = "function", Hint = "Start = function(self) end" },
    Destroy = { Kind = "function", Hint = "Destroy = function(self) end" },
}

local ADAPTER_SCHEMA: Schema = {
    ClassName = { Kind = "string", Hint = 'the Roblox ClassName this adapter teaches, e.g. ClassName = "TextButton"' },
    Extends = { Kind = "string", Hint = 'the adapter this one composes on, e.g. Extends = "GuiButton"' },
    Events = { Kind = "table", Hint = "handler name -> (element, invoke) -> RBXScriptConnection?" },
    Bindable = { Kind = "table", Hint = "property allowlist, e.g. Bindable = { Text = true }" },
    ValueProperty = { Kind = "string", Hint = 'the property Changed watches, e.g. ValueProperty = "Text"' },
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
    if
        descriptor.Tag == nil
        and descriptor.Selector == nil
        and descriptor.Name == nil
        and descriptor.Role == nil
        and descriptor.Group == nil
    then
        fail(
            "Query descriptor needs at least one of Tag, Selector, Name, Role or Group -- "
                .. 'e.g. { Tag = "Unrest", Selector = "TextButton", Role = "ToggleMenu" }.'
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
    if descriptor.Role ~= nil and #descriptor.Role == 0 then
        fail('Query descriptor field "Role" must not be an empty string.')
    end
    if descriptor.Group ~= nil and #descriptor.Group == 0 then
        fail('Query descriptor field "Group" must not be an empty string.')
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
        fail('System definition requires a non-empty string Name, e.g. Name = "MySystem".')
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

--[[
    Validates an adapter definition handed to `AdapterRegistry:Register`.

    Adapters are the one place a mistake is otherwise silent: a typo'd `Bindable` key is
    simply a property that never binds, and a `ClassName` that is not a real Roblox class
    matches nothing, forever, with no error. So this is strict about shape, and the registry
    warns separately when an `Extends` names an adapter nobody registered.
]]
function Resolver.Adapter(value: any): Types.Adapter
    check(value, ADAPTER_SCHEMA, "Adapter definition", true)

    local adapter = value :: Types.Adapter
    if typeof(adapter.ClassName) ~= "string" or #adapter.ClassName == 0 then
        fail('Adapter definition requires a non-empty string ClassName, e.g. ClassName = "TextButton".')
    end

    local events = adapter.Events
    if events ~= nil then
        for key, binder in events do
            if typeof(key) ~= "string" then
                fail(`Adapter "{adapter.ClassName}" has a non-string Events key ({typeof(key)}).`)
            end
            if typeof(binder) ~= "function" then
                fail(
                    `Adapter "{adapter.ClassName}" Events["{key}"] must be a function `
                        .. `(element, invoke) -> RBXScriptConnection?, but got {describe(binder)}.`
                )
            end
        end
    end

    local bindable = adapter.Bindable
    if bindable ~= nil then
        for key, allowed in bindable do
            if typeof(key) ~= "string" then
                fail(`Adapter "{adapter.ClassName}" has a non-string Bindable key ({typeof(key)}).`)
            end
            if typeof(allowed) ~= "boolean" then
                fail(
                    `Adapter "{adapter.ClassName}" Bindable["{key}"] must be a boolean -- Bindable is an `
                        .. `allowlist, so the entry reads {key} = true. Got {describe(allowed)}.`
                )
            end
        end
    end

    return adapter
end

return Resolver
