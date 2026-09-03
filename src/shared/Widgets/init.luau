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

    SCOPES, NOT CALLBACKS THAT LEAK. `OnReady` is handed a cleanup scope alongside the parts.
    Everything the handler wires goes on that scope, and the framework destroys it the moment
    a required part leaves -- untagged, destroyed, moved out of the player's screen. If the
    part comes back, `OnReady` runs again with a fresh scope. Without that, a rebuilt screen
    would wire itself twice and every input would fire two handlers.

    CLIENT ONLY. A widget is a thing on a screen, and the server has no screen. Calling into
    this on the server raises rather than quietly doing nothing, because a caller that got
    here on the server has made a mistake that silence would hide until much later.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Constants = require(script.Parent.Constants)
local Scope = require(script.Parent.Util.Scope)
local Selector = require(script.Parent.Adapters.Selector)
local Types = require(script.Parent.Types)

--[[
    A registered `Each` call. `Found` and `Live` are keyed by group: `Found` is the parts
    collected so far, `Live` the scope handed to `OnReady` for a group that is currently
    complete. A group in `Live` is wired; a group absent from it is not.
]]
type Recipe = {
    Required: { string },
    Needs: { [string]: boolean },
    Wanted: { [string]: boolean },
    OnReady: (group: string, parts: Types.WidgetParts, scope: Types.Scope) -> (),
    Found: { [string]: Types.WidgetParts },
    Live: { [string]: Types.Scope },
}

local Widgets = {}

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

function Widgets.new(elements: Types.ElementManager, tag: string, context: Types.RuntimeContext): Types.WidgetLibrary
    local recipes: { Recipe } = {}
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

    local function admitInto(recipe: Recipe, element: Instance): ()
        local role = Selector.roleOf(element)
        if not recipe.Wanted[role] then
            return
        end
        if not element:IsDescendantOf(screen()) then
            return
        end

        local group = Selector.groupOf(element)
        if group == nil then
            warn(
                `[Unrest.Widgets] {element:GetFullName()} plays "{role}" but sets no {Constants.Attributes.Group}, `
                    .. `so there is no widget for it to join.`
            )
            return
        end

        local parts = recipe.Found[group]
        if parts == nil then
            parts = {}
            recipe.Found[group] = parts
        end
        if parts[role] == element then
            return
        end

        --[[
            A second instance claiming a role a group already filled is a duplicate, not a
            replacement: two knobs under one `UnrestGroup` is a mistake in the screen, and
            silently preferring the later one would wire whichever the walk happened to reach
            last. Keep the first and say so.
        ]]
        local held = parts[role]
        if held ~= nil then
            warn(
                `[Unrest.Widgets] {element:GetFullName()} also plays "{role}" for group "{group}", which `
                    .. `{held:GetFullName()} already fills. Ignoring the second one -- give it its own `
                    .. `{Constants.Attributes.Group}.`
            )
            return
        end

        parts[role] = element
        settle(recipe, group, parts)
    end

    --[[
        Removal is searched by identity rather than by role, because the edit that removed the
        element may be the very edit that changed its role: `Removed` would then report the
        new role and this would clear the wrong slot, leaving a dead instance wired in.
    ]]
    local function expel(element: Instance): ()
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
                for _, recipe in recipes do
                    admitInto(recipe, element)
                end
            end,
            Removed = function(element: Instance)
                expel(element)
            end,
        })
        query = handle
        Scope.add(lifetime, handle)
    end

    local library = {}

    function library:Each(spec: Types.WidgetSpec): Types.WidgetHandle
        client("Each")

        local required = spec.Required
        if #required == 0 then
            error("[Unrest.Widgets] :Each() needs at least one required role, otherwise no group is ever complete.", 2)
        end

        local needs: { [string]: boolean } = {}
        local wanted: { [string]: boolean } = {}
        for _, role in required do
            needs[role] = true
            wanted[role] = true
        end
        if spec.Optional ~= nil then
            for _, role in spec.Optional do
                wanted[role] = true
            end
        end

        local recipe: Recipe = {
            Required = required,
            Needs = needs,
            Wanted = wanted,
            OnReady = spec.OnReady,
            Found = {},
            Live = {},
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
                admitInto(recipe, element)
            end
        end

        --[[
            Written without the colon so its `self` cannot shadow `Each`'s. Nothing here reads
            it: the recipe it retires is the one this call closed over.
        ]]
        local handle: Types.WidgetHandle = {
            Destroy = function(_self: Types.WidgetHandle): ()
                local index = table.find(recipes, recipe)
                if index == nil then
                    return
                end
                table.remove(recipes, index)
                for group in recipe.Live do
                    unsettle(recipe, group)
                end
                table.clear(recipe.Found)
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
    ]]
    function library:Drag(
        scope: Types.Scope,
        handle: Instance,
        track: Instance,
        onMove: (fraction: number) -> (),
        onCommit: ((fraction: number) -> ())?
    ): Types.Scope
        client("Drag")
        expect(handle, "GuiObject", "handle")
        expect(track, "GuiObject", "track")

        local knob = handle :: GuiObject
        local rail = track :: GuiObject

        --- The scope for one gesture. Cleaned on every press, so a drag can never stack.
        local gesture = Scope.scope()
        Scope.add(scope, gesture)

        local function fractionAt(x: number): number
            return math.clamp((x - rail.AbsolutePosition.X) / rail.AbsoluteSize.X, 0, 1)
        end

        Scope.add(
            scope,
            knob.InputBegan:Connect(function(input: InputObject)
                if not isPointerPress(input) then
                    return
                end

                Scope.clean(gesture)
                --[[
                    Seed from where the knob is, not from where the pointer is. A press near
                    the knob's edge would otherwise snap the value by half a knob width before
                    the player has moved at all.
                ]]
                local latest = fractionAt(knob.AbsolutePosition.X + knob.AbsoluteSize.X / 2)

                Scope.addBulk(
                    gesture,
                    UserInputService.InputChanged:Connect(function(moved: InputObject)
                        if not isPointerMove(moved) then
                            return
                        end
                        latest = fractionAt(moved.Position.X)
                        onMove(latest)
                    end),
                    UserInputService.InputEnded:Connect(function(ended: InputObject)
                        if not isPointerPress(ended) then
                            return
                        end
                        -- Stop listening before committing: a handler that tears its own
                        -- widget down must not be doing so from inside a live connection.
                        Scope.clean(gesture)
                        if onCommit ~= nil then
                            onCommit(latest)
                        end
                    end)
                )
            end)
        )

        return gesture
    end

    function library:Destroy(): ()
        table.clear(recipes)
        query = nil
        Scope.destroy(lifetime)
        lifetime = Scope.scope()
    end

    return (library :: any) :: Types.WidgetLibrary
end

return Widgets
