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
    Unrest / Widgets -- `Unrest.Widgets`

    The layer between "a screen full of tagged parts" and "one table per control".

    A widget is several instances that only mean something together: a slider is a track, a
    knob, a fill and a label. The framework adopts them one at a time, in no particular
    order, and hands each one over on its own. Every control would otherwise repeat the same
    bookkeeping -- collect the parts, key them by `UnrestGroup`, wait until the set is
    complete, and start over when the screen is rebuilt. That bookkeeping is this file.

    This is the answer to the problem the whole framework was started for: redrawing a
    control in Studio should not rewrite the code behind it. `Each` names the roles it needs
    and nothing else, so the parts may be renamed, reparented, restyled or replaced wholesale
    and the same handler still finds them.

    ONE QUERY, NOT ONE PER ROLE. Every `Each` call registers a recipe against a single shared
    query over the framework's tag. A query watches each element it holds -- property
    signals, attribute signals, ancestry -- so N queries over the same tag means N sets of
    watchers on the same instances. Four roles across two controls cost one query here rather
    than six.

    ONE SET OF IDENTITY WATCHERS, NOT ONE PER RECIPE. The shared query selects on the tag
    alone, so it never re-announces an element whose `UnrestRole` or `UnrestGroup` was edited:
    the element still carries the tag, so as far as the query is concerned nothing happened.
    A widget is keyed by exactly those two things. So this file keeps one small watcher per
    element in the query -- role, name, group, preset and widget on the element, group,
    preset and widget up its chain, and ancestry -- and moves the element between slots when
    its answer changes. Paid once per element however many `Each` calls there are, and only a
    real change in role, group, screen or widget moves anything; a rename of an element with
    a role attribute is noise and is ignored.

    THE ROOT IS WHERE A GROUP SAYS WHAT IT IS. Every part of a group reads `UnrestGroup` from
    one place: the nearest ancestor that supplies it, or the part itself when it sets its own.
    That instance is the group's root, and it is the only instance `UnrestWidget` is read
    from. A root that names a schema -- "Slider", "Toggle" -- says what the group is, and an
    `Each` given a `Widget` holds only the groups whose root says its name, taking its roles
    from `Schemas` so the caller need not repeat them. A plain `Each` never looks at a root,
    so the two can hold the same group without either noticing. A group whose every part sets
    its own `UnrestGroup` has no shared root and therefore nowhere to carry the attribute;
    that is legal, and `Report` says so rather than leaving it to be found out.

    SCOPES, NOT CALLBACKS THAT LEAK. `OnReady` is handed a cleanup scope alongside the parts.
    Everything the handler wires goes on that scope, and the framework destroys it the moment
    a required part leaves -- untagged, destroyed, moved out of the player's screen. If the
    part comes back, `OnReady` runs again with a fresh scope. Without that, a rebuilt screen
    would wire itself twice and every input would fire two handlers.

    CONTROLS ARE RECIPES THE LIBRARY WROTE ITSELF. `Register` adds a control -- Slider,
    Progress, Toggle, or one a game wrote -- and mounts it on every group whose root says it
    plays that control, whether or not anybody ever calls `Use`. That is not a second
    bookkeeping path: a registered control is one internal `Each` with `Widget` set to its
    name, so a control and a hand-written recipe are told apart by nothing but who wrote them.
    `Use` supplies the config and hands back a way to reach the mounted controls; it does not
    decide what is mounted, because what a group plays is said in Studio.

    STATE OUTLIVES THE MOUNT. A control's value is kept per group, next to the registration
    rather than inside the scope, and is snapshotted when the scope comes down. A screen that
    is rebuilt therefore paints the value it had rather than zero, and paints it in silence:
    `OnChange` is for gestures, and nothing about a rebuild is a gesture. Only the first mount
    of a group reads `Initial`.

    A REPORT, NOT MORE WARNINGS. `Report` and `Explain` answer "why is my widget not wired"
    out of the books this file already keeps: what each recipe found, what it is still
    missing, which duplicates it ignored, and which elements could not join a group at all.
    Neither of them prints. The Output window belongs to mistakes made while the screen runs;
    a question asked from the command bar deserves an answer instead.

    CLIENT ONLY. A widget is a thing on a screen, and the server has no screen. Calling into
    this on the server raises rather than quietly doing nothing, because a caller that got
    here on the server has made a mistake that silence would hide until much later.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Constants = require(script.Parent.Constants)
local Progress = require(script.Controls.Progress)
local Schemas = require(script.Schemas)
local Scope = require(script.Parent.Util.Scope)
local Selector = require(script.Parent.Adapters.Selector)
local Slider = require(script.Controls.Slider)
local Toggle = require(script.Controls.Toggle)
local Types = require(script.Parent.Types)

--- One instance kept out of a group because another already plays its role.
type Duplicate = { Role: string, Kept: Instance, Ignored: Instance }

--[[
    A registered `Each` call. `Found` and `Live` are keyed by group: `Found` is the parts
    collected so far, `Live` the scope handed to `OnReady` for a group that is currently
    complete. A group in `Live` is wired; a group absent from it is not.

    `Widget` is the schema name the recipe insists its groups declare, and `Label` is how
    `Report` and `Explain` name the recipe: that same schema name, or "Each #N".
]]
type Recipe = {
    Widget: string?,
    Schema: Schemas.WidgetSchema?,
    Label: string,
    Required: { string },
    Needs: { [string]: boolean },
    Wanted: { [string]: boolean },
    OnReady: (group: string, parts: Types.WidgetParts, scope: Types.Scope) -> (),
    --[[
        Told when an optional role joins a group that is already wired. `OnReady` cannot
        wait for optional parts -- that is what optional means -- so a handler that paints
        them needs a second knock. Set by the controls; a plain `Each` reads `parts` late.
    ]]
    OnPart: ((group: string, role: string) -> ())?,
    Found: { [string]: Types.WidgetParts },
    Live: { [string]: Types.Scope },
    Duplicates: { [string]: { Duplicate } },
}

--[[
    One watched element of the shared query. `Role`, `Group`, `OnScreen` and `Widget` are the
    answer it was last admitted under, kept so a signal that fires without changing that
    answer -- a rename of an element whose role is set by attribute, say -- does not tear a
    wired widget down only to rebuild it identically.
]]
type Tracked = {
    Watcher: Types.Scope,
    Role: string,
    Group: string?,
    OnScreen: boolean,
    Widget: string?,
}

--[[
    A control the library drives, and the three things about it that outlive any one mount.

    `Values` is the point of the record. The value a group was left at survives the screen
    being rebuilt, so a control that comes back up paints where the player left it instead of
    at zero -- and paints it in silence, because nobody touched anything. It is snapshotted on
    the way down rather than followed on the way through, which is what makes it right for a
    value the game set as well as one the player dragged.

    `Config` is what `Use` supplied, keyed by group and replaced wholesale. `Recipe` is nil
    until the control is materialised; see `materialize`.
]]
type Registration = {
    Control: Types.AnyControl,
    Config: { [string]: any },
    Values: { [string]: any },
    --- What the game is handed: wraps the control's handle to notice a `Set`.
    Live: { [string]: Types.ControlHandle },
    --- The control's own handle, for the library's repaints, which must not count as touches.
    Mounted: { [string]: Types.ControlHandle },
    Recipe: Recipe?,
}

--- Which way a drag measures. `Drag2D` is both at once.
type Axis = "X" | "Y"

local Widgets = {}

--[[
    The attributes that can move an element from one widget to another, on the element itself
    or on any ancestor: its own `UnrestGroup`, a preset that supplies one, and `UnrestWidget`
    on whatever turns out to be the root. Editing any of them anywhere along the chain can
    change which recipe the element belongs to, so all three are watched.
]]
local GROUP_INPUTS = {
    Constants.Attributes.Group,
    Constants.Attributes.Preset,
    Constants.Attributes.Widget,
}

--- Whether the input is the one gesture a drag may start or end with.
local function isPointerPress(input: InputObject): boolean
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

--- Whether the input is a pointer that has moved, which is the only thing a drag follows.
local function isPointerMove(input: InputObject): boolean
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function expect(instance: Instance, className: string, role: string): ()
    if not instance:IsA(className) then
        error(
            `[Unrest.Widgets] Drag needs a {className} for its {role}, but {instance:GetFullName()} is a {instance.ClassName}.`,
            3
        )
    end
end

--[[
    The instance a group is named from, which is the only instance `UnrestWidget` may be read
    on. It is derived from the resolution the framework already does rather than from a rule
    of its own, so the root and the group can never come apart: own attribute first, then the
    preset -- credited to whoever the preset name was typed on -- then the nearest ancestor
    that sets `UnrestGroup`. That is `Selector.attributeIn`'s precedence, read backwards.
]]
local function rootIn(resolved: Selector.Resolution): Instance?
    local instance = resolved.Instance
    if instance:GetAttribute(Constants.Attributes.Group) ~= nil then
        return instance
    end

    local preset = resolved.Preset
    if preset ~= nil and preset[Constants.Attributes.Group] ~= nil then
        if instance:GetAttribute(Constants.Attributes.Preset) ~= nil then
            return instance
        end
        return resolved.Providers[Constants.Attributes.Preset]
    end

    return resolved.Providers[Constants.Attributes.Group]
end

--- The same answer for a caller holding only the instance. Gathers a `Resolution` and drops it.
local function rootOf(instance: Instance): Instance?
    return rootIn(Selector.resolution(instance))
end

--- The schema a root says its group plays. Never inherited, never from a preset: `Constants`
--- keeps `UnrestWidget` out of both, because a widget is a thing, not a default.
local function widgetOn(root: Instance): string?
    local name = root:GetAttribute(Constants.Attributes.Widget)
    if typeof(name) == "string" and #name > 0 then
        return name
    end
    return nil
end

--[[
    The one instance every part of a group reads its group from, or nil when they disagree.
    Disagreement is what "no shared root" means: each part sets its own `UnrestGroup`, which
    assembles perfectly well but leaves nowhere for `UnrestWidget` to go.
]]
local function sharedRoot(parts: { Instance }): Instance?
    local root: Instance? = nil
    for _, part in parts do
        local candidate = rootOf(part)
        if candidate == nil then
            return nil
        end
        if root == nil then
            root = candidate
        elseif candidate ~= root then
            return nil
        end
    end
    return root
end

--- The sentence for a role that has no widget to join, shared by the warning and `Report` so
--- the Output window and the report cannot describe the same mistake two ways.
local function noGroup(element: Instance, role: string): string
    return `{element:GetFullName()} plays "{role}" but sets no {Constants.Attributes.Group}, `
        .. `so there is no widget for it to join.`
end

--- The ClassName playing each role, which is all `Schemas.check` reads.
local function classesOf(parts: Types.WidgetParts): { [string]: string }
    local present: { [string]: string } = {}
    for role, part in parts do
        if part ~= nil then
            present[role] = part.ClassName
        end
    end
    return present
end

--- `Schemas` compares class names and lets the caller decide what "is a" means, because only
--- a caller holding the instances can answer it with `:IsA` -- a `TextButton` is a `GuiButton`.
local function isAIn(parts: Types.WidgetParts): Schemas.IsA
    return function(role: string, _got: string, expected: string): boolean
        local part = parts[role]
        return part ~= nil and part:IsA(expected)
    end
end

--[[
    Where a point falls along one axis of the rail, 0..1.

    `AbsoluteSize` is `0, 0` until the first layout pass. Dividing by it would hand `onMove`
    NaN, which `math.clamp` passes straight through and a caller would then write into a
    `UDim2`. A track with no size has no position along it, so answer with its start -- and
    with its start even when inverted, because zero size is an absence, not an extreme.
]]
local function fractionAlong(rail: GuiObject, point: Vector2, axis: Axis, invert: boolean): number
    local size = if axis == "X" then rail.AbsoluteSize.X else rail.AbsoluteSize.Y
    if size <= 0 then
        return 0
    end

    local origin = if axis == "X" then rail.AbsolutePosition.X else rail.AbsolutePosition.Y
    local along = if axis == "X" then point.X else point.Y
    local fraction = math.clamp((along - origin) / size, 0, 1)
    return if invert then 1 - fraction else fraction
end

--[[
    The gesture itself, which every drag entry point shares.

    `Drag` and `Drag2D` disagree about exactly one thing -- what a pointer position *means*,
    a fraction along one axis or one on each -- so that is the only thing they pass in. The
    press, the seed, the move and the release are written once here.
]]
local function gesture<Value>(
    scope: Types.Scope,
    knob: GuiObject,
    measure: (Vector2) -> Value,
    onMove: (Value) -> (),
    onCommit: ((Value) -> ())?
): Types.Scope
    --- The scope for one gesture. Cleaned on every press, so a drag can never stack.
    local live = Scope.scope()
    Scope.add(scope, live)

    Scope.add(
        scope,
        knob.InputBegan:Connect(function(input: InputObject)
            if not isPointerPress(input) then
                return
            end

            Scope.clean(live)
            --[[
                Seed from where the knob is, not from where the pointer is. A press near the
                knob's edge would otherwise snap the value by half a knob width before the
                player has moved at all.
            ]]
            local latest = measure(knob.AbsolutePosition + knob.AbsoluteSize / 2)

            Scope.addBulk(
                live,
                UserInputService.InputChanged:Connect(function(moved: InputObject)
                    if not isPointerMove(moved) then
                        return
                    end
                    latest = measure(Vector2.new(moved.Position.X, moved.Position.Y))
                    onMove(latest)
                end),
                UserInputService.InputEnded:Connect(function(ended: InputObject)
                    if not isPointerPress(ended) then
                        return
                    end
                    -- Stop listening before committing: a handler that tears its own
                    -- widget down must not be doing so from inside a live connection.
                    Scope.clean(live)
                    if onCommit ~= nil then
                        onCommit(latest)
                    end
                end)
            )
        end)
    )

    return live
end

function Widgets.new(elements: Types.ElementManager, tag: string, context: Types.RuntimeContext): Types.WidgetLibrary
    local recipes: { Recipe } = {}
    --- Counts every `Each` ever registered, so "Each #3" names the same recipe all run long.
    local registered = 0
    local lifetime = Scope.scope()
    local query: Types.QueryHandle? = nil
    local playerGui: Instance? = nil

    local function client(method: string): ()
        if context ~= "Client" then
            error(`[Unrest.Widgets] :{method}() is client-only -- the server has no screen to find widgets on.`, 3)
        end
    end

    --[[
        Only the player's own screens count, and this is the filter that decides it.

        A tagged screen exists twice while the game runs: the template in `StarterGui` and
        the copy `PlayerGui` was given. Both sit in the DataModel, both carry the tag, and
        both are adopted -- so a query on a role returns two of everything. Worse, the two
        copies share their group names, so whichever arrives first claims the group and the
        other is dropped. When that is the template, the player's own control never wires up
        and nothing appears to happen at all.

        Resolved once, before any query work, because `Added` fires synchronously from inside
        `Query` and yielding there would suspend the walk that is still finding elements.
    ]]
    local function screen(): Instance
        local resolved = playerGui
        if resolved == nil then
            resolved = Players.LocalPlayer:WaitForChild("PlayerGui")
            playerGui = resolved
        end
        return resolved :: Instance
    end

    --- Fires `OnReady` if this group has just become complete and is not already wired.
    local function settle(recipe: Recipe, group: string, parts: Types.WidgetParts): ()
        if recipe.Live[group] ~= nil then
            return
        end
        for _, role in recipe.Required do
            if parts[role] == nil then
                return
            end
        end

        local scope = Scope.scope()
        recipe.Live[group] = scope
        Scope.add(lifetime, scope)
        recipe.OnReady(group, parts, scope)
    end

    --- Tears a wired group down. Everything `OnReady` put on the scope goes with it.
    local function unsettle(recipe: Recipe, group: string): ()
        local scope = recipe.Live[group]
        if scope == nil then
            return
        end
        recipe.Live[group] = nil
        Scope.remove(lifetime, scope)
        Scope.destroy(scope)
    end

    local tracked: { [Instance]: Tracked } = {}

    local function admitInto(recipe: Recipe, element: Instance, at: Tracked): ()
        if not recipe.Wanted[at.Role] then
            return
        end
        if not at.OnScreen then
            return
        end

        local group = at.Group
        if group == nil then
            warn(`[Unrest.Widgets] {noGroup(element, at.Role)}`)
            return
        end

        --[[
            A recipe that names a widget holds only the groups that say they are that widget,
            and the group says it on its root. A plain recipe never asks, so the two kinds
            can hold the same group at the same time without either of them noticing.
        ]]
        if recipe.Widget ~= nil and at.Widget ~= recipe.Widget then
            return
        end

        local parts = recipe.Found[group]
        if parts == nil then
            parts = {}
            recipe.Found[group] = parts
        end
        if parts[at.Role] == element then
            return
        end

        --[[
            A second instance claiming a role a group already filled is a duplicate, not a
            replacement: two knobs under one `UnrestGroup` is a mistake in the screen, and
            silently preferring the later one would wire whichever the walk happened to reach
            last. Keep the first, say so, and remember the pair -- `Report` is asked about it
            long after the warning has scrolled out of the Output window.
        ]]
        local held = parts[at.Role]
        if held ~= nil then
            warn(
                `[Unrest.Widgets] {element:GetFullName()} also plays "{at.Role}" for group "{group}", which `
                    .. `{held:GetFullName()} already fills. Ignoring the second one -- give it its own `
                    .. `{Constants.Attributes.Group}.`
            )

            local ignored = recipe.Duplicates[group]
            if ignored == nil then
                ignored = {}
                recipe.Duplicates[group] = ignored
            end
            for _, entry in ignored do
                if entry.Role == at.Role and entry.Kept == held and entry.Ignored == element then
                    return
                end
            end
            table.insert(ignored, { Role = at.Role, Kept = held, Ignored = element })
            return
        end

        local wasLive = recipe.Live[group] ~= nil
        parts[at.Role] = element
        settle(recipe, group, parts)
        --- A part that joined a group already wired is, by definition, an optional one.
        if wasLive and recipe.OnPart ~= nil then
            recipe.OnPart(group, at.Role)
        end
    end

    --[[
        A remembered duplicate outlives neither of the two instances it is about: once either
        has left the query or moved to another group, the pair says nothing true any more.
    ]]
    local function forget(element: Instance): ()
        for _, recipe in recipes do
            for group, ignored in recipe.Duplicates do
                for index = #ignored, 1, -1 do
                    local entry = ignored[index]
                    if entry.Kept == element or entry.Ignored == element then
                        table.remove(ignored, index)
                    end
                end
                if #ignored == 0 then
                    recipe.Duplicates[group] = nil
                end
            end
        end
    end

    --[[
        Removal is searched by identity rather than by role, because the edit that removed the
        element may be the very edit that changed its role: reading the role now would give
        the new one and clear the wrong slot, leaving a dead instance wired in. `rekey` below
        relies on this too, since it runs precisely after the role or group has changed.
    ]]
    local function expel(element: Instance): ()
        forget(element)

        for _, recipe in recipes do
            for group, parts in recipe.Found do
                for role, part in parts do
                    if part ~= element then
                        continue
                    end

                    parts[role] = nil
                    if recipe.Needs[role] then
                        unsettle(recipe, group)
                    end
                    if next(parts) == nil then
                        recipe.Found[group] = nil
                    end
                    break
                end
            end
        end
    end

    --[[
        The four things that decide where an element belongs, read fresh off one walk of the
        ancestor chain. The widget name is the root's, not the element's, and is only asked
        for once the element has a group at all -- without one there is no root to ask.
    ]]
    local function identify(element: Instance): (string, string?, boolean, string?)
        local resolved = Selector.resolution(element)
        local group = Selector.groupIn(resolved)

        local widget: string? = nil
        if group ~= nil then
            local root = rootIn(resolved)
            if root ~= nil then
                widget = widgetOn(root)
            end
        end

        return Selector.roleOf(element), group, element:IsDescendantOf(screen()), widget
    end

    --[[
        Re-asks where a watched element belongs and moves it if the answer changed. The
        element leaves whatever slot it held first, so a widget it was required by comes down,
        and is then offered to every recipe again under its new role, group and widget, so a
        widget it now completes comes up. Nothing happens when the answer is the same as last
        time -- including `UnrestWidget` on the root, which is why editing it while the game
        runs moves a whole group out of one recipe and into another.
    ]]
    local function rekey(element: Instance): ()
        local record = tracked[element]
        if record == nil then
            return
        end

        local role, group, onScreen, widget = identify(element)
        if
            role == record.Role
            and group == record.Group
            and onScreen == record.OnScreen
            and widget == record.Widget
        then
            return
        end
        record.Role = role
        record.Group = group
        record.OnScreen = onScreen
        record.Widget = widget

        expel(element)
        for _, recipe in recipes do
            admitInto(recipe, element, record)
        end
    end

    --[[
        The whole chain is watched, not only the ancestor supplying the group today: a nearer
        one that sets `UnrestGroup` tomorrow takes precedence the moment it does. Cleaned and
        refilled on reparent rather than added to, so connections to ancestors the element no
        longer has do not accumulate. The same shape `Query` uses for a `Group` filter.
    ]]
    local function bindChain(element: Instance, chain: Types.Scope, onChanged: () -> ()): ()
        Scope.clean(chain)
        for _, ancestor in Selector.ancestorChain(element) do
            for _, attribute in GROUP_INPUTS do
                Scope.add(chain, ancestor:GetAttributeChangedSignal(attribute):Connect(onChanged))
            end
        end
    end

    --- Starts following an element's role, group and widget for as long as the query holds
    --- it, and hands back where it belongs so the caller need not ask a second time.
    local function follow(element: Instance): Tracked
        local existing = tracked[element]
        if existing ~= nil then
            return existing
        end

        local watcher = Scope.scope()
        Scope.add(lifetime, watcher)
        local chain = Scope.add(watcher, Scope.scope())

        local role, group, onScreen, widget = identify(element)
        local record: Tracked = {
            Watcher = watcher,
            Role = role,
            Group = group,
            OnScreen = onScreen,
            Widget = widget,
        }
        tracked[element] = record

        local function onChanged(): ()
            rekey(element)
        end

        Scope.addBulk(
            watcher,
            -- `Name` stands in for the role when no attribute sets one.
            element:GetPropertyChangedSignal("Name"):Connect(onChanged),
            element:GetAttributeChangedSignal(Constants.Attributes.Role):Connect(onChanged),
            element:GetAttributeChangedSignal(Constants.Attributes.Group):Connect(onChanged),
            element:GetAttributeChangedSignal(Constants.Attributes.Preset):Connect(onChanged),
            -- An element that sets its own group is its own root, so the widget name it plays
            -- can be edited right here rather than on an ancestor.
            element:GetAttributeChangedSignal(Constants.Attributes.Widget):Connect(onChanged),
            --[[
                Moving anywhere above the element changes which ancestors supply its group and
                whether it is still on the player's screen. Rebind the chain first so the new
                ancestors are watched before their answer is read.
            ]]
            element.AncestryChanged:Connect(function()
                bindChain(element, chain, onChanged)
                rekey(element)
            end)
        )
        bindChain(element, chain, onChanged)

        return record
    end

    local function unfollow(element: Instance): ()
        local record = tracked[element]
        if record == nil then
            return
        end
        tracked[element] = nil
        Scope.remove(lifetime, record.Watcher)
        Scope.destroy(record.Watcher)
        forget(element)
    end

    --[[
        The shared query, opened by the first `Each` and kept for the life of the library.
        It selects on the tag alone: a role filter would need one query per role, and the
        role test here is a hash lookup that costs less than a second set of watchers.
    ]]
    local function open(): ()
        if query ~= nil then
            return
        end
        local handle = elements:Query({ Tag = tag }, {
            Added = function(element: Instance)
                local record = follow(element)
                for _, recipe in recipes do
                    admitInto(recipe, element, record)
                end
            end,
            Removed = function(element: Instance)
                unfollow(element)
                expel(element)
            end,
        })
        query = handle
        Scope.add(lifetime, handle)
    end

    --- Roles a group holds right now, sorted, so two reports of the same screen read alike.
    local function rolesIn(parts: Types.WidgetParts): { string }
        local roles: { string } = {}
        for role, part in parts do
            if part ~= nil then
                table.insert(roles, role)
            end
        end
        table.sort(roles)
        return roles
    end

    --- The parts themselves, for a caller that wants the instances rather than the roles.
    local function instancesIn(parts: Types.WidgetParts): { Instance }
        local held: { Instance } = {}
        for _, role in rolesIn(parts) do
            local part = parts[role]
            if part ~= nil then
                table.insert(held, part)
            end
        end
        return held
    end

    --- Required roles this group is still waiting for, sorted.
    local function missingIn(recipe: Recipe, parts: Types.WidgetParts): { string }
        local missing: { string } = {}
        for _, role in recipe.Required do
            if parts[role] == nil then
                table.insert(missing, role)
            end
        end
        table.sort(missing)
        return missing
    end

    --- Every group a recipe has an opinion about, sorted: the ones it holds parts for and the
    --- ones it has wired, which are the same set except for a heartbeat during teardown.
    local function groupsIn(recipe: Recipe): { string }
        local names: { string } = {}
        local seen: { [string]: boolean } = {}
        for group in recipe.Found do
            if not seen[group] then
                seen[group] = true
                table.insert(names, group)
            end
        end
        for group in recipe.Live do
            if not seen[group] then
                seen[group] = true
                table.insert(names, group)
            end
        end
        table.sort(names)
        return names
    end

    --- Elements the query holds that resolve to `group`, for questions about a group no
    --- recipe managed to assemble.
    local function elementsOf(group: string): { Instance }
        local held: { Instance } = {}
        for element, at in tracked do
            if at.OnScreen and at.Group == group then
                table.insert(held, element)
            end
        end
        return held
    end

    --- Whether any recipe currently holds this element as one of a group's parts.
    local function heldSomewhere(element: Instance): boolean
        for _, recipe in recipes do
            for _, parts in recipe.Found do
                for _, part in parts do
                    if part == element then
                        return true
                    end
                end
            end
        end
        return false
    end

    --- Whether this element is already accounted for as a duplicate of some group's role.
    local function ignoredSomewhere(element: Instance): boolean
        for _, recipe in recipes do
            for _, ignored in recipe.Duplicates do
                for _, entry in ignored do
                    if entry.Ignored == element then
                        return true
                    end
                end
            end
        end
        return false
    end

    --[[
        Elements playing a role some recipe wants that could not join a group at all, and the
        reason the first interested recipe would give. The three answers are the three gates
        in `admitInto`, in the order it applies them.
    ]]
    local function orphans(): { { Instance: Instance, Role: string, Reason: string } }
        local found: { { Instance: Instance, Role: string, Reason: string } } = {}

        for element, at in tracked do
            if heldSomewhere(element) or ignoredSomewhere(element) then
                continue
            end
            --[[
                The `StarterGui` template is outside the player's screen by design -- it is
                the thing the screen was copied from -- so listing every part of it would
                bury the one orphan that matters under a copy of every widget on the place.
                Anything else outside `PlayerGui` is still reported, because a widget parented
                somewhere unexpected is exactly what an orphan list is for.
            ]]
            if not at.OnScreen and element:IsDescendantOf(StarterGui) then
                continue
            end

            local reason: string? = nil
            for _, recipe in recipes do
                if not recipe.Wanted[at.Role] then
                    continue
                end
                if not at.OnScreen then
                    reason = "outside PlayerGui"
                elseif at.Group == nil then
                    reason = noGroup(element, at.Role)
                elseif recipe.Widget ~= nil and at.Widget ~= recipe.Widget then
                    reason = `root plays {at.Widget or "nothing"}, recipe wants {recipe.Widget}`
                end
                if reason ~= nil then
                    break
                end
            end

            if reason ~= nil then
                table.insert(found, { Instance = element, Role = at.Role, Reason = reason })
            end
        end

        table.sort(found, function(a, b)
            if a.Role ~= b.Role then
                return a.Role < b.Role
            end
            return a.Instance:GetFullName() < b.Instance:GetFullName()
        end)
        return found
    end

    --[[
        One sentence about one group as one recipe sees it. The wording is the contract: the
        Studio tooling reads the same schemas in edit mode and says the same thing, so a lint
        finding and the Output window at Play cannot describe one screen two ways.
    ]]
    local function sentence(recipe: Recipe, group: string, parts: Types.WidgetParts): string
        local missing = missingIn(recipe, parts)
        if #missing > 0 then
            return `[Unrest.Widgets] group "{group}" is not a complete {recipe.Label}: `
                .. `missing {table.concat(missing, ", ")}.`
        end

        --[[
            Class is a schema's business, so only a recipe that named one asks. A group can be
            complete and wired and still be answered this way: the runtime assembles by role
            and never refuses a part for its class, which is exactly why saying so is useful.
        ]]
        local schema = recipe.Schema
        if schema ~= nil then
            local wrong = Schemas.check(classesOf(parts), schema, isAIn(parts)).WrongClass
            if #wrong > 0 then
                local clauses: { string } = {}
                for _, entry in wrong do
                    table.insert(clauses, `{entry.Role} is a {entry.Got}, needs a {entry.Expected}`)
                end
                return `[Unrest.Widgets] group "{group}" is not a complete {recipe.Label}: `
                    .. `{table.concat(clauses, "; ")}.`
            end
        end

        return `[Unrest.Widgets] group "{group}" is a complete {recipe.Label} and is wired.`
    end

    local library = {}
    --- The library named by its public type, minted up front because a control's `Mount` is
    --- handed it and controls are mounted from inside this constructor's own closures.
    local typed = (library :: any) :: Types.WidgetLibrary

    --[[
        Registers a recipe against the shared query and hands it back.

        `Each` wraps one in a handle; a control keeps one. Both come through here so there is
        exactly one place that decides what a recipe is and when the query opens. `label` is
        the name `Report` and `Explain` give it: a control supplies its own, and a plain `Each`
        takes the next number -- which is why a control does not consume one.
    ]]
    local function define(spec: Types.WidgetSpec, label: string?): Recipe
        --[[
            `Widget` names a schema, and the schema supplies the roles so the caller does not
            restate what Studio already knows. A name nobody registered is a typo, and a typo
            here silently holds no groups at all, so it raises and lists what there is.
        ]]
        local widget = spec.Widget
        local schema: Schemas.WidgetSchema? = nil
        if widget ~= nil then
            schema = Schemas.Get(widget)
            if schema == nil then
                error(
                    `[Unrest.Widgets] :Each() asks for the widget "{widget}", which no schema is registered under. `
                        .. `Registered: {table.concat(Schemas.List(), ", ")}.`,
                    3
                )
            end
        end

        --- Roles written in the spec win: a caller naming a widget *and* its roles means the
        --- roles, and the widget then only says which groups to look at.
        local required = spec.Required
        local optional = spec.Optional
        if schema ~= nil then
            required = required or schema.Required
            optional = optional or schema.Optional
        end
        if required == nil or #required == 0 then
            error("[Unrest.Widgets] :Each() needs at least one required role, otherwise no group is ever complete.", 3)
        end
        local roles: { string } = required :: { string }

        local needs: { [string]: boolean } = {}
        local wanted: { [string]: boolean } = {}
        for _, role in roles do
            needs[role] = true
            wanted[role] = true
        end
        if optional ~= nil then
            for _, role in optional do
                wanted[role] = true
            end
        end

        --- A control brings its own label; a plain `Each` takes the next number, which is why
        --- the counter only moves when nobody supplied one.
        if label == nil then
            registered += 1
        end

        local recipe: Recipe = {
            Widget = widget,
            Schema = schema,
            Label = label or widget or `Each #{registered}`,
            Required = roles,
            Needs = needs,
            Wanted = wanted,
            OnReady = spec.OnReady,
            Found = {},
            Live = {},
            Duplicates = {},
        }
        table.insert(recipes, recipe)

        --[[
            Resolve the screen before touching the query. `Added` fires synchronously for the
            elements that already match, so the `WaitForChild` inside `screen` has to have
            happened by then or it would yield in the middle of that walk.
        ]]
        screen()

        local existing = query
        if existing == nil then
            -- Opening the query replays the current set through every recipe, this one included.
            open()
        else
            -- The query is already open, so it will not announce elements it has already seen.
            for _, element in existing:Elements() do
                admitInto(recipe, element, follow(element))
            end
        end

        return recipe
    end

    --- Takes a recipe out of the run: its wired groups come down, its books are emptied, and
    --- the shared query stays for everybody else.
    local function retire(recipe: Recipe): ()
        local index = table.find(recipes, recipe)
        if index == nil then
            return
        end
        table.remove(recipes, index)
        for group in recipe.Live do
            unsettle(recipe, group)
        end
        table.clear(recipe.Found)
        table.clear(recipe.Duplicates)
    end

    --[[
        Every control registered, in registration order, and the record for each. The order is
        kept beside the map so materialisation and error messages read the same way twice.
    ]]
    local controls: { [string]: Registration } = {}
    local controlOrder: { string } = {}

    local function controlNames(): { string }
        local names = table.clone(controlOrder)
        table.sort(names)
        return names
    end

    --[[
        Mounts one group of one control, and arranges for its value to outlive the mount.

        The snapshot is a cleanup function rather than a subscription to `Changed`, and that is
        the whole reason it is right: `Changed` only knows about gestures, while what has to
        survive is the value whatever it came from -- a drag, a `Set` from the game, an
        `Initial`. Reading it on the way down catches all three with one closure.
    ]]
    local function drive(registration: Registration, group: string, parts: Types.WidgetParts, scope: Types.Scope): ()
        local handle = registration.Control.Mount(typed, group, parts, scope, registration.Config[group])

        --- A group mounted before, on a screen that has since been rebuilt, comes back where
        --- it was. `Set` paints and calls nothing back, so this is invisible from the game.
        local remembered = registration.Values[group]
        if remembered ~= nil then
            handle:Set(remembered)
        end

        --[[
            Only a value somebody chose is worth remembering: a gesture, a `Set` from the
            game, or a value carried over from an earlier mount. The default a control paints
            when it has nothing else is not a choice, and remembering it would make the
            first `Use` with an `Initial` lose to the auto-mount that ran before it.
        ]]
        local touched = remembered ~= nil
        Scope.add(
            scope,
            handle.Changed:Connect(function()
                touched = true
            end)
        )
        local given: Types.ControlHandle = {
            Get = function(_self: Types.ControlHandle): any
                return handle:Get()
            end,
            Set = function(_self: Types.ControlHandle, value: any): ()
                handle:Set(value)
                touched = true
            end,
            Changed = handle.Changed,
        }

        registration.Live[group] = given
        registration.Mounted[group] = handle
        Scope.add(scope, function()
            if touched then
                registration.Values[group] = handle:Get()
            end
            if registration.Live[group] == given then
                registration.Live[group] = nil
                registration.Mounted[group] = nil
            end
        end)
    end

    --[[
        Opens the recipe for every control that is registered but not yet driving anything.

        Deferred rather than done as each control is registered, for one reason: a recipe opens
        the shared query, and opening it resolves the player's screen. Doing that while
        `require(Unrest)` is still returning would make requiring the framework yield, and
        would put watchers on a screen before the game had asked for anything. So the built-ins
        wait for `Unrest:Start`, which calls `library:Start` on the client -- or for the first
        call into the library, whichever comes first -- exactly as the query itself waits for
        the first `Each`.
    ]]
    local function materialize(): ()
        for _, name in controlOrder do
            local registration = controls[name]
            if registration == nil or registration.Recipe ~= nil then
                continue
            end

            local control = registration.Control
            local recipe = define({
                Widget = control.Name,
                OnReady = function(group: string, parts: Types.WidgetParts, scope: Types.Scope)
                    drive(registration, group, parts, scope)
                end,
            }, control.Name)
            --- A fill or a label that arrives after the mount is painted by repainting the
            --- value the control already holds. Through the inner handle: not a touch.
            recipe.OnPart = function(group: string, _role: string)
                local mounted = registration.Mounted[group]
                if mounted ~= nil then
                    mounted:Set(mounted:Get())
                end
            end
            registration.Recipe = recipe
        end
    end

    --[[
        Replaces a control's config and re-mounts whatever it is already driving.

        A group can be mounted before `Use` is ever called -- that is the point of the design --
        and such a group is holding the config that existed at the time, which is none. So the
        config is not merged into a live mount, it is remounted onto: the value is remembered
        across it, nothing is called back, and nothing is published.

        The table is copied rather than held, so a caller that keeps editing theirs afterwards
        does not change a control's behaviour without saying so.
    ]]
    local function apply(registration: Registration, config: { [string]: any }?): ()
        registration.Config = if config ~= nil then table.clone(config) else {}

        local recipe = registration.Recipe
        if recipe == nil then
            return
        end

        --- Collected first: the loop below empties `Live` and refills it as it goes.
        local live: { string } = {}
        for group in registration.Live do
            table.insert(live, group)
        end

        for _, group in live do
            local parts = recipe.Found[group]
            unsettle(recipe, group)
            if parts ~= nil then
                settle(recipe, group, parts)
            end
        end
    end

    --[[
        Records a control, replacing one of the same name.

        Replacement is intentional, the same way it is in `Schemas.Register` and
        `Presets.Register`: a game that wants "Slider" to mean something else says so in one
        place. What it was driving comes down and goes back up on the new control, at the
        values it was left at.

        A control that names a schema nobody has registered registers its own, because
        carrying the schema is the whole reason a control has the field -- but it never
        replaces a registered one, since that would let requiring a module quietly redefine
        what "Slider" means for every screen in the place.
    ]]
    local function record(control: Types.AnyControl): Registration
        if typeof(control) ~= "table" then
            error(`[Unrest.Widgets] :Register() expects a control table, got {typeof(control)}.`, 0)
        end

        local name = control.Name
        if typeof(name) ~= "string" or name == "" then
            error("[Unrest.Widgets] :Register() expects a control with a non-empty Name.", 0)
        end
        if typeof(control.Mount) ~= "function" then
            error(`[Unrest.Widgets] control "{name}" has no Mount function.`, 0)
        end

        local schema = control.Schema
        if typeof(schema) ~= "table" then
            error(`[Unrest.Widgets] control "{name}" carries no Schema.`, 0)
        end
        if schema.Name ~= name then
            error(
                `[Unrest.Widgets] control "{name}" carries the schema "{schema.Name}". A control drives the schema `
                    .. `of its own name, so the two have to agree.`,
                0
            )
        end
        if Schemas.Get(name) == nil then
            Schemas.Register(schema)
        end

        local existing = controls[name]
        if existing ~= nil then
            local recipe = existing.Recipe
            if recipe ~= nil then
                retire(recipe)
                existing.Recipe = nil
            end
            existing.Control = control
            return existing
        end

        local registration: Registration = {
            Control = control,
            Config = {},
            Values = {},
            Mounted = {},
            Live = {},
            Recipe = nil,
        }
        controls[name] = registration
        table.insert(controlOrder, name)
        return registration
    end

    function library:Each(spec: Types.WidgetSpec): Types.WidgetHandle
        client("Each")
        materialize()

        local recipe = define(spec)

        --[[
            Written without the colon so their `self` cannot shadow `Each`'s. Nothing here
            reads it: the recipe all three touch is the one this call closed over.
        ]]
        local handle: Types.WidgetHandle = {
            Destroy = function(_self: Types.WidgetHandle): ()
                retire(recipe)
            end,

            Get = function(_self: Types.WidgetHandle, group: string): Types.WidgetParts?
                --- Parts of a group that is merely half-collected are not a widget, and
                --- handing them out would let a caller read a role that is about to arrive.
                if recipe.Live[group] == nil then
                    return nil
                end
                return recipe.Found[group]
            end,

            Groups = function(_self: Types.WidgetHandle): { string }
                local live: { string } = {}
                for group in recipe.Live do
                    table.insert(live, group)
                end
                table.sort(live)
                return live
            end,
        }

        return handle
    end

    --[[
        Adds a control the library drives itself.

        Registering is not the same as asking for one. Every group whose root carries
        `UnrestWidget = control.Name` and whose required roles are present is mounted on it,
        whether or not anybody calls `Use` -- what a group plays is said in Studio, and a
        screen drawn there should work without a line of Luau to switch it on. Registering
        after such a group is already on screen still mounts it: the recipe replays the query.
    ]]
    --[[
        Mounts the registered controls. `Unrest:Start` calls this on the client, so a screen
        whose root says `UnrestWidget = "Slider"` is driven whether or not the game ever
        touches this library -- that is the whole promise of declaring a widget in Studio.
        Idempotent, and cheap after the first call: `materialize` skips controls that already
        have a recipe.
    ]]
    function library:Start(): ()
        client("Start")
        materialize()
    end

    function library:Register(control: Types.AnyControl): ()
        client("Register")
        record(control)
        materialize()
    end

    --[[
        Supplies a registered control's config, keyed by `UnrestGroup`, and hands back a way to
        reach the controls it is driving.

        A group with no entry is still mounted and still works; it simply reacts to nothing,
        because nothing said what its value means. Calling `Use` twice for the same control
        replaces the config rather than adding to it -- it is the control's config, not a
        subscription -- and `Destroy` on the handle clears it without unmounting anything.
    ]]
    function library:Use(name: string, config: { [string]: any }?): Types.ControlUseHandle
        client("Use")
        materialize()

        local registration = controls[name]
        if registration == nil then
            error(
                `[Unrest.Widgets] :Use("{name}") -- no control is registered under that name. `
                    .. `Registered: {table.concat(controlNames(), ", ")}.`,
                2
            )
        end

        --[[
            No config means "hand me the handles", not "forget the config": a caller reaching
            for `Get` must not tear down every mount -- and the drag in flight on one of them --
            as the price of asking. Only a config supplied here replaces the one in force.
        ]]
        if config ~= nil then
            apply(registration, config)
        end

        --- Same shape as an `Each` handle and deliberately not the same type: `Get` answers
        --- with the control driving a group, and `Destroy` unmounts nothing.
        local handle: Types.ControlUseHandle = {
            Destroy = function(_self: Types.ControlUseHandle): ()
                apply(registration, nil)
            end,

            Get = function(_self: Types.ControlUseHandle, group: string): Types.ControlHandle?
                return registration.Live[group]
            end,

            Groups = function(_self: Types.ControlUseHandle): { string }
                local live: { string } = {}
                for group in registration.Live do
                    table.insert(live, group)
                end
                table.sort(live)
                return live
            end,
        }

        return handle
    end

    --[[
        Drag is built on `handle`'s own `InputBegan` and the global `InputChanged` /
        `InputEnded`, rather than on the framework's `Press` handler, for two reasons.

        The first is correctness, and it is the whole reason this helper exists.
        `GuiObject.InputEnded` only fires while the pointer is still over the instance, and a
        drag leaves the knob within the first twenty pixels. A drag ended by the knob's own
        release would simply never end. `UserInputService.InputEnded` fires wherever the
        pointer is.

        The second is cost. Binding `Press` means a live query, and a query for a single
        instance you already hold is a set of watchers, a cascade ledger and an adapter
        resolution to learn something the caller already knew. One connection answers it.

        The consequence worth knowing: `handle` does not have to be tagged or adopted. Any
        GuiObject can be a knob.

        `options` chooses the axis and which end is zero. A vertical slider is almost always
        `{ Axis = "Y", Invert = true }`, because a track measures downwards and a volume does
        not.
    ]]
    function library:Drag(
        scope: Types.Scope,
        handle: Instance,
        track: Instance,
        onMove: (fraction: number) -> (),
        onCommit: ((fraction: number) -> ())?,
        options: Types.DragOptions?
    ): Types.Scope
        client("Drag")
        expect(handle, "GuiObject", "handle")
        expect(track, "GuiObject", "track")

        local rail = track :: GuiObject
        local axis: Axis = if options ~= nil and options.Axis ~= nil then options.Axis else "X"
        local invert = options ~= nil and options.Invert == true

        return gesture(scope, handle :: GuiObject, function(point: Vector2): number
            return fractionAlong(rail, point, axis, invert)
        end, onMove, onCommit)
    end

    --- The same gesture, measured on both axes at once. A pad, a colour square, a minimap
    --- marker: things whose value is a place rather than an amount.
    function library:Drag2D(
        scope: Types.Scope,
        handle: Instance,
        track: Instance,
        onMove: (position: Vector2) -> (),
        onCommit: ((position: Vector2) -> ())?
    ): Types.Scope
        client("Drag2D")
        expect(handle, "GuiObject", "handle")
        expect(track, "GuiObject", "track")

        local rail = track :: GuiObject

        return gesture(scope, handle :: GuiObject, function(point: Vector2): Vector2
            return Vector2.new(fractionAlong(rail, point, "X", false), fractionAlong(rail, point, "Y", false))
        end, onMove, onCommit)
    end

    --[[
        Everything every recipe knows, arranged so two calls over an unchanged screen render
        identically: recipes in registration order, groups sorted inside each, every list of
        roles sorted. Nothing here prints and nothing here is a warning.
    ]]
    function library:Report(): Types.WidgetReport
        client("Report")
        --- A report that hid the built-in controls would be answering a different question
        --- from the one that was asked, so asking for one is enough to open their recipes.
        materialize()

        local groups: { Types.WidgetGroupReport } = {}
        for _, recipe in recipes do
            for _, group in groupsIn(recipe) do
                local parts = recipe.Found[group] or {}
                local root = sharedRoot(instancesIn(parts))

                local duplicates: { Duplicate } = {}
                local ignored = recipe.Duplicates[group]
                if ignored ~= nil then
                    duplicates = table.clone(ignored)
                    table.sort(duplicates, function(a, b)
                        return a.Role < b.Role
                    end)
                end

                table.insert(groups, {
                    Group = group,
                    Root = root,
                    Widget = if root ~= nil then widgetOn(root) else nil,
                    Recipe = recipe.Label,
                    Present = rolesIn(parts),
                    Missing = missingIn(recipe, parts),
                    Duplicates = duplicates,
                    Live = recipe.Live[group] ~= nil,
                })
            end
        end

        return { Groups = groups, Orphans = orphans() }
    end

    --[[
        One group, in prose: a line per recipe that has seen it, plus the line about a group
        that has no root to declare itself on, because that is the answer to "why does my
        `Widget = "Slider"` recipe not see it" and no recipe can say it.
    ]]
    function library:Explain(group: string): string
        client("Explain")
        materialize()

        local lines: { string } = {}
        for _, recipe in recipes do
            local parts = recipe.Found[group]
            if parts == nil and recipe.Live[group] == nil then
                continue
            end
            table.insert(lines, sentence(recipe, group, parts or {}))
        end

        local held = elementsOf(group)
        if #held > 0 and sharedRoot(held) == nil then
            table.insert(
                lines,
                `[Unrest.Widgets] group "{group}" has no shared root: every part sets its own `
                    .. `{Constants.Attributes.Group}, so it cannot carry {Constants.Attributes.Widget}.`
            )
        end

        if #lines == 0 then
            return `[Unrest.Widgets] no recipe has seen a group "{group}".`
        end
        return table.concat(lines, "\n")
    end

    function library:Destroy(): ()
        table.clear(recipes)
        table.clear(tracked)
        query = nil
        Scope.destroy(lifetime)
        lifetime = Scope.scope()

        --[[
            The controls stay registered -- registration is a fact about the library, not
            about a screen -- but everything they were driving went with the lifetime, so
            every book kept about a group is now about a group that no longer exists. The
            next call into the library materialises them again from nothing.
        ]]
        for _, registration in controls do
            registration.Recipe = nil
            table.clear(registration.Live)
            table.clear(registration.Values)
            table.clear(registration.Config)
        end
    end

    --[[
        The three controls the framework knows how to drive. Recorded here and materialised
        later: `Widgets.new` runs while `require(Unrest)` is still returning, and a recipe
        opens the shared query. See `materialize`.
    ]]
    record(Slider)
    record(Progress)
    record(Toggle)

    return typed
end

return Widgets
