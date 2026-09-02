--!strict
--[[
    Unrest / Net / Validate

    Payload validation, driven entirely by `ArgumentSpec`. The server runs this on every
    request before a handler or an `Authorize` hook sees it, so neither ever receives a shape
    it did not ask for.

    The posture is a whitelist, not a blacklist. A value is rejected unless it is one of a
    short list of plain data kinds:

        nil  boolean  number  string  table  Vector3  Color3  EnumItem

    Everything else -- Instance, function, thread, coroutine, userdata, a table with a
    metatable, a table that points at itself -- is refused without being inspected. That
    matters more than it looks: an `Instance` in a payload is a live reference into the data
    model that a handler might write through, a metatable turns `payload.Anything` into
    attacker-chosen code, and a cyclic table turns any recursive walk into a hang. None of
    those are validated *carefully*; they are simply never accepted.

    Everything is also bounded, because the cost of checking is itself an attack surface:
    `Constants.Limits` caps string length, table depth, and entries per table, and the walk
    stops at the first failure.

    This module is deliberately self-contained -- it knows nothing about commands, players,
    or remotes, so it is the same code on both sides of the wire and can be reasoned about
    on its own.
]]

local Constants = require(script.Parent.Parent.Constants)
local NetTypes = require(script.Parent.Types)

type ArgumentSpec = NetTypes.ArgumentSpec

local Limits = Constants.Limits

--- The complete list of userdata kinds a payload may contain. Adding to this list is a
--- security decision, not a convenience: each one must be immutable, cheap to compare, and
--- meaningless as a reference into the data model.
local ALLOWED_USERDATA: { [string]: boolean } = table.freeze({
    Vector3 = true,
    Color3 = true,
    EnumItem = true,
})

local Validate = {}

local function isFinite(value: number): boolean
    -- NaN fails its own equality test; the infinities are named. Both would sail through a
    -- naive Min/Max comparison, so they are rejected before bounds are considered at all.
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function describe(path: string): string
    return if path == "" then "the payload" else `payload{path}`
end

local function childPathFor(path: string, key: any): string
    return if typeof(key) == "string" then `{path}.{key}` else `{path}[{tostring(key)}]`
end

--- `string.find` is used rather than `string.match` so a pattern with captures still tells us
--- where it started and ended: a full match is `1 .. #value`, and nothing shorter counts.
local function matchesInFull(value: string, pattern: string): boolean
    local ok, first, last = pcall(string.find, value, pattern)
    if not ok then
        -- A malformed pattern is the contract author's bug. Fail closed rather than throw
        -- out of the gateway.
        return false
    end
    return first == 1 and last == #value
end

local checkValue: (
    value: any,
    spec: ArgumentSpec?,
    path: string,
    depth: number,
    seen: { [any]: boolean }
) -> (boolean, string?)

--[[
    Structural checks every table gets, whether or not a schema describes it. `spec` only adds
    per-entry expectations on top; it can never relax depth, entry count, metatables or cycles.
]]
local function checkTable(
    value: any,
    spec: ArgumentSpec?,
    path: string,
    depth: number,
    seen: { [any]: boolean }
): (boolean, string?)
    if depth > Limits.MaxPayloadDepth then
        return false, `{describe(path)} nests deeper than {Limits.MaxPayloadDepth} levels`
    end
    if seen[value] then
        return false, `{describe(path)} is a cyclic table`
    end
    if getmetatable(value :: any) ~= nil then
        return false, `{describe(path)} has a metatable, which a payload may never carry`
    end

    seen[value] = true

    local fields = if spec ~= nil then spec.Fields else nil
    local of = if spec ~= nil then spec.Of else nil
    local count = 0

    for key, entry in value :: { [any]: any } do
        count += 1
        if count > Limits.MaxPayloadEntries then
            seen[value] = nil
            return false, `{describe(path)} has more than {Limits.MaxPayloadEntries} entries`
        end

        local keyKind = typeof(key)
        if keyKind == "string" then
            if #(key :: string) > Limits.MaxStringLength then
                seen[value] = nil
                return false, `{describe(path)} has a key longer than {Limits.MaxStringLength} characters`
            end
        elseif keyKind == "number" then
            if not isFinite(key :: number) then
                seen[value] = nil
                return false, `{describe(path)} has a non-finite numeric key`
            end
        else
            seen[value] = nil
            return false, `{describe(path)} has a {keyKind} key; only string and number keys are accepted`
        end

        local child = childPathFor(path, key)
        local childSpec: ArgumentSpec? = nil

        if fields ~= nil then
            -- Named-field schema: unknown fields are refused rather than ignored. Deny by
            -- default applies inside a payload too -- an undeclared field is not free space.
            if keyKind ~= "string" then
                seen[value] = nil
                return false, `{describe(path)} declares named fields, so a {keyKind} key is not accepted`
            end
            childSpec = fields[key :: string]
            if childSpec == nil then
                seen[value] = nil
                return false, `{describe(child)} is not declared by the schema`
            end
        elseif of ~= nil then
            childSpec = of
        end

        local ok, detail = checkValue(entry, childSpec, child, depth + 1, seen)
        if not ok then
            seen[value] = nil
            return false, detail
        end
    end

    if fields ~= nil then
        for name, fieldSpec in fields do
            if (value :: { [any]: any })[name] == nil and fieldSpec.Optional ~= true then
                seen[value] = nil
                return false, `{describe(childPathFor(path, name))} is required`
            end
        end
    end

    seen[value] = nil
    return true, nil
end

--- The whitelist walk used wherever no schema describes a value: it still may not be an
--- Instance, a function, oversized, too deep, or self-referential.
local function checkPlain(value: any, path: string, depth: number, seen: { [any]: boolean }): (boolean, string?)
    local kind = typeof(value)

    if value == nil or kind == "boolean" then
        return true, nil
    end
    if kind == "number" then
        if not isFinite(value :: number) then
            return false, `{describe(path)} is not a finite number`
        end
        return true, nil
    end
    if kind == "string" then
        if #(value :: string) > Limits.MaxStringLength then
            return false, `{describe(path)} is longer than {Limits.MaxStringLength} characters`
        end
        return true, nil
    end
    if ALLOWED_USERDATA[kind] then
        return true, nil
    end
    if kind == "table" then
        return checkTable(value, nil, path, depth, seen)
    end

    return false, `{describe(path)} is a {kind}, which is never accepted in a payload`
end

function checkValue(
    value: any,
    spec: ArgumentSpec?,
    path: string,
    depth: number,
    seen: { [any]: boolean }
): (boolean, string?)
    if spec == nil then
        return checkPlain(value, path, depth, seen)
    end

    if value == nil then
        if spec.Optional == true or spec.Kind == "nil" then
            return true, nil
        end
        return false, `{describe(path)} is required and must be a {spec.Kind}`
    end

    local kind = typeof(value)

    if spec.Kind == "nil" then
        return false, `{describe(path)} must be nil`
    elseif spec.Kind == "integer" or spec.Kind == "number" then
        if kind ~= "number" then
            return false, `{describe(path)} must be a {spec.Kind}, got {kind}`
        end
        if not isFinite(value :: number) then
            return false, `{describe(path)} is not a finite number`
        end
        if spec.Kind == "integer" and (value :: number) % 1 ~= 0 then
            return false, `{describe(path)} must be a whole number`
        end
    elseif kind ~= spec.Kind then
        return false, `{describe(path)} must be a {spec.Kind}, got {kind}`
    end

    if spec.OneOf ~= nil and table.find(spec.OneOf, value) == nil then
        return false, `{describe(path)} is not one of the values the schema allows`
    end

    if kind == "string" then
        local text = value :: string
        -- The contract's own MaxLength can only ever be stricter than the global ceiling.
        local cap = math.min(spec.MaxLength or Limits.MaxStringLength, Limits.MaxStringLength)
        if #text > cap then
            return false, `{describe(path)} is longer than {cap} characters`
        end
        local pattern = spec.Pattern
        if pattern ~= nil and not matchesInFull(text, pattern) then
            return false, `{describe(path)} does not match the pattern the schema requires`
        end
    elseif kind == "number" then
        local number = value :: number
        if spec.Min ~= nil and number < spec.Min then
            return false, `{describe(path)} is below the minimum of {spec.Min}`
        end
        if spec.Max ~= nil and number > spec.Max then
            return false, `{describe(path)} is above the maximum of {spec.Max}`
        end
    elseif kind == "Vector3" then
        local vector = value :: Vector3
        if not isFinite(vector.X) or not isFinite(vector.Y) or not isFinite(vector.Z) then
            return false, `{describe(path)} has a non-finite component`
        end
    elseif kind == "table" then
        return checkTable(value, spec, path, depth, seen)
    end

    return true, nil
end

--[[
    Validates a whole payload against a command's `Payload` spec.

    A command that declares no `Payload` accepts nil and nothing else. That is the deny-by-
    default rule again, one level down: a command cannot be handed data it never asked for,
    so a handler written against `nil` can never be surprised by a table.
]]
function Validate.Payload(spec: ArgumentSpec?, payload: any): (boolean, string?)
    if spec == nil then
        if payload ~= nil then
            return false, `this command declares no payload and accepts only nil, got {typeof(payload)}`
        end
        return true, nil
    end
    return checkValue(payload, spec, "", 1, {})
end

--[[
    Validates a value about to leave the server on a channel.

    A channel with no `Value` spec is *not* unchecked: the plain-data whitelist still runs, so
    an Instance can never be replicated by accident. That is what keeps a channel carrying a
    character Model honest -- flipping its visibility would not leak the Model, it would fail
    validation and refuse to replicate.
]]
function Validate.Value(spec: ArgumentSpec?, value: any): (boolean, string?)
    return checkValue(value, spec, "", 1, {})
end

return Validate
