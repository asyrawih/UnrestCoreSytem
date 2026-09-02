--!strict
--[[
    Unrest / Bridge / Selector

    Pure matching. Turns a validated descriptor into a `CompiledSelector` and answers the
    single question "does this Instance match?".

    Deliberately knows nothing about *how* candidates arrive -- CollectionService signals,
    a subtree scan, or a caller poking at it by hand. Query owns sourcing; Selector owns the
    predicate. That split is what makes the predicate re-runnable when an element is renamed.
]]

local CollectionService = game:GetService("CollectionService")

local Resolver = require(script.Parent.Resolver)
local Types = require(script.Parent.Parent.Types)

local Selector = {}

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
        Ancestor = validated.Ancestor,
        Recursive = if validated.Recursive == nil then true else validated.Recursive,
        Text = "",
    }
    compiled.Text = Selector.describe(compiled)

    return compiled
end

--- The predicate. Cheap enough to re-run on every rename / tag change.
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
