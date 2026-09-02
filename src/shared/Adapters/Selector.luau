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

    The cascade rule -- which instances the framework tag manages -- is defined here too,
    for the same reason `ancestorChain` is: `Elements` decides what to adopt and `Query`
    decides what a descriptor matches, and if those two walked the tree separately a
    cascaded button would be adopted, wired, and invisible to the query that asked for it.
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
    Where every walk in this module stops climbing: the DataModel, and the services parented
    straight to it. A tag or an attribute on `Players` or on `StarterGui` is configuration for
    the whole place, and nothing here is allowed to mean that.
]]
local function isBoundary(instance: Instance): boolean
    if instance == game then
        return true
    end
    local parent = instance.Parent
    return parent ~= nil and parent == game
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
        if isBoundary(ancestor) then
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

--------------------------------------------------------------------------------
-- The cascade
--------------------------------------------------------------------------------

--[[
    The framework tag manages the instance it is on *and* every `GuiObject` under it, so a
    screen is opted in by tagging its container once. Three functions carry that rule and
    nothing else re-derives it:

        isManaged     -- the predicate: does the framework manage this one instance?
        cascadeUnder  -- the enumeration: what does it manage under this root?
        isGate        -- which un-managed instances a caller must still watch, so that an
                         `UnrestIgnore` edit is never missed without a connection per
                         descendant.

    `Elements` adopts with them and `Query` sources with them.
]]

local IGNORE = Constants.Attributes.Ignore

--[[
    `UnrestIgnore = true`, and nothing looser.

    A boolean, because the attribute answers a yes/no question and Studio's attribute editor
    offers a checkbox for exactly that. `"true"` typed into a string attribute is not it, and
    treating it as if it were would make the one attribute that *removes* elements from the
    framework the one attribute that guesses.
]]
local function isIgnored(instance: Instance): boolean
    return instance:GetAttribute(IGNORE) == true
end

--[[
    Whether the cascade arrives at `instance` at all -- the tag question with the `GuiObject`
    test left out, so it can also be asked about a Folder that only *carries* managed things.

    Nearest answer wins, and `UnrestIgnore` is read before the tag at every step: an instance
    that is both tagged and ignored manages itself and stops the cascade below it, which is
    the only reading under which both attributes still mean what they say.

    Unlike `ancestorChain` this walk does not stop at a `LayerCollector`. An inheritable
    attribute stops there because a group that leaked past a ScreenGui would start selecting
    elements on unrelated screens -- it is ambient context. A tag is not ambient: somebody put
    it on one specific container on purpose, and tagging a Folder full of ScreenGuis is a
    thing they may well have meant.
]]
local function cascadeReaches(instance: Instance): boolean
    if isBoundary(instance) or isIgnored(instance) then
        return false
    end
    if CollectionService:HasTag(instance, Constants.Tag) then
        return true
    end

    local current: Instance? = instance.Parent
    while current ~= nil do
        local ancestor: Instance = current
        if isBoundary(ancestor) or isIgnored(ancestor) then
            return false
        end
        if CollectionService:HasTag(ancestor, Constants.Tag) then
            return true
        end
        current = ancestor.Parent
    end

    return false
end

--[[
    Whether a descriptor's `Tag` is the one that cascades.

    Only the framework's own tag does. `Tag = "Highlighted"` in a query still means exactly
    the instances somebody put that tag on -- a foreign tag is a label, not an opt-in, and
    silently selecting everything under a labelled Frame would be a surprise nobody asked for.
]]
function Selector.cascades(tag: string): boolean
    return tag == Constants.Tag
end

--[[
    The one question. An instance is managed when it carries the framework tag, or when it is
    a `GuiObject` the cascade reaches.

    A direct tag is unconditional, including inside an ignored subtree: `UnrestIgnore` opts a
    subtree out of a *cascade*, and tagging one `UIStroke` inside it to bind a channel to its
    colour has to keep working. That is also why the `GuiObject` test sits after the tag and
    not before it -- a `UIListLayout` is never swept up, but it is adopted the moment somebody
    tags it themselves.
]]
function Selector.isManaged(instance: Instance): boolean
    if CollectionService:HasTag(instance, Constants.Tag) then
        return true
    end
    if not instance:IsA("GuiObject") then
        return false
    end
    return cascadeReaches(instance)
end

--[[
    Whether an instance that the cascade does not manage can still change what it manages, and
    so has to be watched.

    Two kinds qualify: an instance carrying `UnrestIgnore`, because clearing it re-adopts
    everything beneath, and a non-`GuiObject` the cascade descends *through* -- a Folder --
    because setting `UnrestIgnore` on one releases everything beneath.

    This is the whole reason the framework does not need a connection per descendant. Managed
    elements are watched because they are managed; these are the only other instances whose
    `UnrestIgnore` can matter, and there are a handful of them in a screen rather than one per
    `UICorner`.
]]
function Selector.isGate(instance: Instance): boolean
    if isIgnored(instance) then
        return true
    end
    return not instance:IsA("GuiObject") and #instance:GetChildren() > 0
end

--[[
    The gates on the path from `instance` up to, but not including, `root`.

    A sweep finds the gates that exist when it runs; an arrival can create one. A Folder that
    was empty when the screen was swept is a Folder the cascade now descends through, and its
    `UnrestIgnore` starts mattering the moment something lands inside it -- so the containers
    above an arriving element are re-tested rather than assumed to be unchanged.
]]
function Selector.gatesAbove(instance: Instance, root: Instance): { Instance }
    local found: { Instance } = {}

    local current: Instance? = instance
    while current ~= nil and current ~= root do
        local candidate: Instance = current
        if isBoundary(candidate) then
            break
        end
        if Selector.isGate(candidate) then
            table.insert(found, candidate)
        end
        current = candidate.Parent
    end

    return found
end

--[[
    Everything the cascade manages under `root`, and the gates a caller must watch to keep
    that answer live. Empty when the cascade does not reach `root` at all -- so it is safe to
    call on a tagged root, and equally on an instance whose `UnrestIgnore` was just cleared.

    `root` itself is never included: the caller already has it, and it is managed by its own
    tag rather than by the cascade.

    Every instance returned in the first list satisfies `isManaged`, and every instance under
    `root` that satisfies `isManaged` is in it or carries its own tag -- the walk prunes at
    exactly what the predicate refuses to walk past. The two agree by construction, which is
    the point of them living side by side.
]]
function Selector.cascadeUnder(root: Instance): ({ Instance }, { Instance })
    local managed: { Instance } = {}
    local gates: { Instance } = {}

    if not cascadeReaches(root) then
        return managed, gates
    end

    -- Iterative, so a deeply nested screen cannot land on a recursion limit.
    local frontier: { Instance } = root:GetChildren()
    local index = 1
    while index <= #frontier do
        local instance = frontier[index]
        index += 1

        if Selector.isGate(instance) then
            table.insert(gates, instance)
        end

        if isIgnored(instance) then
            -- Pruned. The gate above keeps it observable, so clearing the attribute later
            -- brings the whole subtree back without anything having watched it meanwhile.
            continue
        end

        if instance:IsA("GuiObject") then
            table.insert(managed, instance)
        end

        for _, child in instance:GetChildren() do
            table.insert(frontier, child)
        end
    end

    return managed, gates
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

    Coverage is not in here. Whether an element is still reached by a cascading tag is a
    question about the chain above it rather than about the descriptor, so `Query` pays for
    those watches only when it sources from the framework tag.
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
    --[[
        The framework tag reads through `isManaged`, so a button adopted by cascade is a
        button `Query` can find. Sourcing knows the same rule; this is the half that decides
        whether a candidate stayed in the set.
    ]]
    local tag = compiled.Tag
    if tag ~= nil then
        if Selector.cascades(tag) then
            if not Selector.isManaged(instance) then
                return false
            end
        elseif not CollectionService:HasTag(instance, tag) then
            return false
        end
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
