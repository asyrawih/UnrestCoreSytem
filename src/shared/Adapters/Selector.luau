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
local Presets = require(script.Parent.Parent.Presets)
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

--[[
    The ancestors an inheritable attribute may be read from, nearest first.

    Two boundaries, and both matter. The walk stops after the first `LayerCollector`, because
    a screen is the widest thing an inherited value can sensibly mean -- a group that leaked
    past the ScreenGui would start selecting elements on unrelated screens. It also stops
    before `game` and before anything parented straight to it, so a stray attribute on a
    service can never be read as framework configuration.

    This is the single definition of the walk. `Elements` resolves inherited attributes with
    it and `Query` watches the chain it returns, so the two can never disagree about which
    ancestors count.
]]
function Selector.ancestorChain(instance: Instance): { Instance }
    local chain: { Instance } = {}

    local current: Instance? = instance.Parent
    while current ~= nil do
        local ancestor: Instance = current
        if ancestor == game then
            break
        end

        local parent = ancestor.Parent
        if parent ~= nil and parent == game then
            break
        end

        table.insert(chain, ancestor)

        if ancestor:IsA("LayerCollector") then
            break
        end
        current = ancestor.Parent
    end

    return chain
end

--[[
    The group a preset supplies, if the element names one.

    This mirrors the middle layer of `Elements`' resolution. Without it a preset could set
    `element.Group` while `Query({ Group = ... })` quietly failed to match the same element --
    two answers to one question, which is the kind of bug nobody finds by reading.
]]
local function presetGroup(instance: Instance): string?
    local name = instance:GetAttribute(Constants.Attributes.Preset)
    if typeof(name) ~= "string" or #name == 0 then
        return nil
    end

    local preset = Presets.Get(name)
    if preset == nil then
        return nil
    end

    local group = preset[Constants.Attributes.Group]
    if typeof(group) == "string" and #group > 0 then
        return group
    end
    return nil
end

local function readGroup(instance: Instance): string?
    local group = instance:GetAttribute(Constants.Attributes.Group)
    if typeof(group) == "string" and #group > 0 then
        return group
    end
    return nil
end

--[[
    `UnrestGroup`, from the element or the nearest ancestor that sets one. No fallback to the
    instance name, on purpose: a group is something a designer states, never something the
    framework guesses.

    Inheriting here is what makes the attribute worth having. A group is context -- every
    element on a screen shares the answer -- so it is written once on the ScreenGui, and
    `Query({ Group = "MainMenu" })` still selects the lot. `roleOf` deliberately does NOT
    walk: a role is identity, and inheriting one would give every descendant of a panel the
    same name.
]]
function Selector.groupOf(instance: Instance): string?
    local own = readGroup(instance)
    if own ~= nil then
        return own
    end

    local fromPreset = presetGroup(instance)
    if fromPreset ~= nil then
        return fromPreset
    end

    for _, ancestor in Selector.ancestorChain(instance) do
        local inherited = readGroup(ancestor)
        if inherited ~= nil then
            return inherited
        end
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
        -- A preset can supply the group, so swapping presets can move an element in or out.
        table.insert(attributes, Constants.Attributes.Preset)
    end

    return properties, attributes
end

--[[
    Whether this selector's answer can be changed by an instance other than the candidate.

    Only `Group` inherits, so only `Group` makes a query depend on the chain above each
    element. A caller that ignores this still matches correctly on the first pass; it just
    stops being live when a group is edited on a ScreenGui rather than on the element.
]]
function Selector.watchesAncestors(compiled: Types.CompiledSelector): boolean
    return compiled.Group ~= nil
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
