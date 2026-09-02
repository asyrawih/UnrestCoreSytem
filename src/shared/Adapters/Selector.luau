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

    Two rules live here that a reader might expect to find in `Elements`, and both are here
    for the same reason. `Elements` decides what to adopt and what an element's attributes are
    worth; `Query` decides what a descriptor matches. Every time one of those questions has
    been answered in two places, the two answers have drifted -- so:

        the cascade      -- `isManaged` / `cascadeUnder` / `isGate`, which instances the tag
                            manages, or a cascaded button is adopted, wired, and invisible to
                            the query that asked for it;
        the resolution   -- `ancestorChain` / `inheritedProviders` / `presetFor` /
                            `attributeOf`, what an attribute is worth, or the framework reports
                            a group on an element that no query can find.

    `Elements` and `Query` are callers of both. Neither holds a second opinion.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = require(script.Parent.Parent.Constants)
local Presets = require(script.Parent.Parent.Presets)
local Resolver = require(script.Parent.Parent.Util.Resolver)
local Types = require(script.Parent.Parent.Types)

local Selector = {}

local ATTRIBUTES = Constants.Attributes

--- `Constants.Inheritable` as a lookup. Cast once here rather than at every read site.
local INHERITABLE: { [string]: boolean } = (Constants.Inheritable :: any) :: { [string]: boolean }

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
-- Attribute resolution
--------------------------------------------------------------------------------

--[[
    One question, one answer: *what is attribute X worth on this instance?*

    `Elements` asks it to build `element.Attributes`, `Selector` asks it to decide what a
    descriptor matches. It used to be answered twice -- `Elements` merged three layers while
    `Selector` read the instance -- and the two duly drifted apart, so a preset on a ScreenGui
    could name a group the framework reported on a button and a query could not find. They
    call the same functions now, and the precedence lives in exactly one of them.

    Text for `AttributeSource` is built here too. Provenance is a fact about the resolution,
    and it belongs beside the rule that produced it rather than beside the code that prints it.
]]

local function ownSource(): Types.AttributeSource
    return { Origin = "Own", Text = "set here" }
end

local function presetSource(preset: string): Types.AttributeSource
    return { Origin = "Preset", Preset = preset, Text = `from preset "{preset}"` }
end

local function inheritedSource(ancestor: Instance): Types.AttributeSource
    return {
        Origin = "Inherited",
        Ancestor = ancestor,
        Text = `inherited from {ancestor.Name} ({ancestor.ClassName})`,
    }
end

--[[
    The nearest ancestor that sets each of `names`, found in one pass over `ancestorChain`.
    A name missing from the result is a name nobody above sets.

    Callers that also have to *watch* the chain walk `ancestorChain` themselves for that --
    the whole chain is watched, not only today's providers, because a nearer ancestor that
    sets the attribute tomorrow has to win the moment it does.
]]
function Selector.inheritedProviders(instance: Instance, names: { string }): { [string]: Instance }
    local providers: { [string]: Instance } = {}

    for _, ancestor in Selector.ancestorChain(instance) do
        for _, name in names do
            if not providers[name] and ancestor:GetAttribute(name) ~= nil then
                providers[name] = ancestor
            end
        end
    end

    return providers
end

local PRESET_ONLY: { string } = { ATTRIBUTES.Preset }

--[[
    The preset that applies to `instance`: the name it resolves to, the declared bundle under
    that name, and where the name was written.

    `UnrestPreset` is itself inheritable, so a whole screen can be handed a default bundle from
    its ScreenGui -- but the element's own naming of a preset beats the inherited one. A preset
    never names a preset, so this layer reads the attribute and nothing else.

    The name comes back even when nothing is declared under it, and so does its source: a
    misspelled preset is a warning `Elements` has to be able to write, pointing at the instance
    the name was actually typed on.
]]
function Selector.presetFor(instance: Instance): (string?, Presets.Preset?, Types.AttributeSource?)
    local name = instance:GetAttribute(ATTRIBUTES.Preset)
    local source: Types.AttributeSource? = if name ~= nil then ownSource() else nil

    if name == nil then
        local provider: Instance? = Selector.inheritedProviders(instance, PRESET_ONLY)[ATTRIBUTES.Preset]
        if provider ~= nil then
            name = provider:GetAttribute(ATTRIBUTES.Preset)
            source = inheritedSource(provider)
        end
    end

    if typeof(name) ~= "string" or #name == 0 then
        return nil, nil, source
    end
    return name, Presets.Get(name), source
end

--[[
    The value of `name` on `instance`, and the layer that supplied it. Most specific wins:

        the element's own attribute  >  its preset's entry  >  the nearest ancestor's

    The last layer applies only to the names in `Constants.Inheritable`, because the rule is
    *inherit context, never intent*: `UnrestGroup` says which screen an element is on and every
    element on that screen shares the answer, whereas inheriting `UnrestCommand` would silently
    arm every descendant of a panel. `UnrestPreset` skips the middle layer -- a preset naming a
    preset would be a second, invisible level of indirection.

    This is the single definition of that precedence. `Elements` resolves every key of
    `element.Attributes` through it and `Selector.groupOf` answers with it, so what the
    framework reports about an element and what a query matches on cannot come apart.
]]
function Selector.attributeOf(instance: Instance, name: string): (any, Types.AttributeSource?)
    local own = instance:GetAttribute(name)
    if own ~= nil then
        return own, ownSource()
    end

    if name ~= ATTRIBUTES.Preset then
        local presetName, preset = Selector.presetFor(instance)
        if presetName ~= nil and preset ~= nil then
            local value = preset[name]
            if value ~= nil then
                return value, presetSource(presetName)
            end
        end
    end

    if INHERITABLE[name] then
        local provider: Instance? = Selector.inheritedProviders(instance, { name })[name]
        if provider ~= nil then
            return provider:GetAttribute(name), inheritedSource(provider)
        end
    end

    return nil, nil
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
    `UnrestGroup`, resolved. No fallback to the instance name, on purpose: a group is something
    a designer states, never something the framework guesses.

    Every layer of the answer comes from `attributeOf`, which is the same call `Elements` makes
    when it fills in `element.Attributes` -- so a group supplied by a preset on a ScreenGui is
    a group `Query({ Group = ... })` finds, and `element.Group` and the query cannot report
    different things about the same button.

    That inheritance is what makes the attribute worth having: a group is context, so it is
    written once on the ScreenGui and selects the lot. `roleOf` deliberately does NOT walk --
    a role is identity, and inheriting one would give every descendant of a panel the same name.
]]
function Selector.groupOf(instance: Instance): string?
    local group = Selector.attributeOf(instance, ATTRIBUTES.Group)
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
    The same question asked of the chain above the candidate: which attributes, edited on an
    ancestor, can move this element in or out of the set?

    Exactly the inheritable ones among `triggers` -- derived from that list rather than listed
    again, so a filter that starts reading a new attribute cannot gain an element watch and
    quietly miss the ancestor one. Today that is `UnrestGroup` and `UnrestPreset`: a group is
    inherited, and so is the preset that can supply a group, which is why watching `UnrestGroup`
    alone left a query stale the moment somebody swapped the preset on a ScreenGui.

    `UnrestRole` never appears here, because a role does not inherit.
]]
function Selector.ancestorTriggers(compiled: Types.CompiledSelector): { string }
    local names: { string } = {}

    local _, attributes = Selector.triggers(compiled)
    for _, name in attributes do
        if INHERITABLE[name] then
            table.insert(names, name)
        end
    end

    return names
end

--[[
    Whether this selector's answer can be changed by an instance other than the candidate.

    Answered from `ancestorTriggers`, so "does the chain matter?" and "what is watched on it?"
    are one decision. A caller that ignores this still matches correctly on the first pass; it
    just stops being live when a group is edited on a ScreenGui rather than on the element.
]]
function Selector.watchesAncestors(compiled: Types.CompiledSelector): boolean
    return #Selector.ancestorTriggers(compiled) > 0
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
