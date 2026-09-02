--!strict
--[[
    Unrest / Adapters / Selector

    Pure matching. Turns a validated descriptor into a `CompiledSelector` and answers the
    single question "does this Instance match?".

    Deliberately knows nothing about *how* candidates arrive -- CollectionService signals,
    a subtree scan, or a caller poking at it by hand. Query owns sourcing; Selector owns the
    predicate. That split is what makes the predicate re-runnable the moment an element is
    renamed or one of its attributes changes.

    `Role` is the field to reach for. `Name` is what a designer will change the afternoon
    after you ship, whereas `UnrestRole` is a contract they set on purpose -- so `Role`
    matches the attribute *or*, when the attribute is absent, the name. Naming a button
    `ToggleMenu` therefore keeps working, and setting `UnrestRole = "ToggleMenu"` on a button
    called `Btn_04_final` starts working, without the query changing either way.

    `Group` has no such fallback: an element is in a group only if somebody said so.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Parent.Constants)
local Resolver = require(script.Parent.Parent.Util.Resolver)
local Types = require(script.Parent.Parent.Types)

local Selector = {}

--- `UnrestRole`, or the instance's name when the attribute is not set.
function Selector.roleOf(instance: Instance): string
    local role = instance:GetAttribute(Constants.Attributes.Role)
    if typeof(role) == "string" and #role > 0 then
        return role
    end
    return instance.Name
end

--- `UnrestGroup`, or nil. No fallback, on purpose.
function Selector.groupOf(instance: Instance): string?
    local group = instance:GetAttribute(Constants.Attributes.Group)
    if typeof(group) == "string" and #group > 0 then
        return group
    end
    return nil
end

--- Renders a selector the way the whiteboard wrote it, for use in error messages.
function Selector.describe(compiled: Types.CompiledSelector): string
    local parts: { string } = {}

    if compiled.Tag ~= nil then
        table.insert(parts, `Tag = "{compiled.Tag}"`)
    end
    if compiled.Selector ~= nil then
        table.insert(parts, `is:A("{compiled.Selector}")`)
    end
    if compiled.Name ~= nil then
        table.insert(parts, `Name = "{compiled.Name}"`)
    end
    if compiled.Role ~= nil then
        table.insert(parts, `Role = "{compiled.Role}"`)
    end
    if compiled.Group ~= nil then
        table.insert(parts, `Group = "{compiled.Group}"`)
    end
    if compiled.Ancestor ~= nil then
        local scope = if compiled.Recursive then "under" else "directly in"
        table.insert(parts, `{scope} {compiled.Ancestor:GetFullName()}`)
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Validates a descriptor (via the Resolver) and fills in defaults.
function Selector.parse(descriptor: Types.Descriptor): Types.CompiledSelector
    local validated = Resolver.Descriptor(descriptor)

    local compiled: Types.CompiledSelector = {
        Tag = validated.Tag,
        Selector = validated.Selector,
        Name = validated.Name,
        Role = validated.Role,
        Group = validated.Group,
        Ancestor = validated.Ancestor,
        Recursive = if validated.Recursive == nil then true else validated.Recursive,
        Text = "",
    }
    compiled.Text = Selector.describe(compiled)

    return compiled
end

--[[
    Which of an element's properties and attributes can move it in or out of this result
    set. Query watches exactly these and nothing else, so a selector that filters on class
    alone costs one connection per element rather than four.

    `Role` implies watching `Name` too, because that is what it falls back to.
]]
function Selector.triggers(compiled: Types.CompiledSelector): ({ string }, { string })
    local properties: { string } = {}
    local attributes: { string } = {}

    if compiled.Name ~= nil or compiled.Role ~= nil then
        table.insert(properties, "Name")
    end
    if compiled.Role ~= nil then
        table.insert(attributes, Constants.Attributes.Role)
    end
    if compiled.Group ~= nil then
        table.insert(attributes, Constants.Attributes.Group)
    end

    return properties, attributes
end

--- The predicate. Cheap enough to re-run on every rename, tag change or attribute change.
function Selector.matches(instance: Instance, compiled: Types.CompiledSelector): boolean
    local tag = compiled.Tag
    if tag ~= nil and not CollectionService:HasTag(instance, tag) then
        return false
    end

    local className = compiled.Selector
    if className ~= nil and not instance:IsA(className) then
        return false
    end

    local name = compiled.Name
    if name ~= nil and instance.Name ~= name then
        return false
    end

    local role = compiled.Role
    if role ~= nil and Selector.roleOf(instance) ~= role then
        return false
    end

    local group = compiled.Group
    if group ~= nil and Selector.groupOf(instance) ~= group then
        return false
    end

    local ancestor = compiled.Ancestor
    if ancestor ~= nil then
        if compiled.Recursive then
            if not instance:IsDescendantOf(ancestor) then
                return false
            end
        elseif instance.Parent ~= ancestor then
            return false
        end
    end

    return true
end

return Selector
