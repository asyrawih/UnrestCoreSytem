--!strict
--[[
    Two helpers that turn "a screen full of tagged parts" into "one table per widget".

    Neither of these is framework code. They are the glue a game writes once because the
    framework has no Controls layer yet -- see `docs/PROPOSAL-CONTROLS.md`, where exactly this
    shape is the thing being proposed. When that lands, this file goes away.

    WHAT `each` SOLVES. A widget is several instances that only mean something together, and
    the framework hands them over one at a time, in no particular order. Waiting until a group
    is complete, and keeping one table per group, is bookkeeping every widget would otherwise
    repeat.

    WHAT `drag` SOLVES. `GuiObject.InputEnded` only fires while the pointer is still over the
    instance, and a drag leaves it within the first twenty pixels. Built on the knob's own
    `Release`, a drag would never end.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Scythe = require(ReplicatedStorage.Packages.Scythe)
local Selector = require(ReplicatedStorage.Unrest.Adapters.Selector)
local Types = require(ReplicatedStorage.Unrest.Types)

export type Parts = { [string]: Instance? }

local Widget = {}

--[[
    Calls `onReady(group, parts)` once, per `UnrestGroup`, as soon as every role in `required`
    has been adopted for that group. `parts` is keyed by role.

    `optional` roles are collected the same way but never hold the call back. One that has
    arrived by then is in `parts`; one that arrives later is added to the same table, so a
    caller that keeps the reference sees it appear. Nothing fires twice.

    The group is read with `Selector.groupOf` rather than `Elements:Get(...).Group`, because
    Query and Elements keep separate ledgers: a query's `Added` can fire before Elements has
    adopted the instance, and the group would read as absent even though the attribute is set.
]]
function Widget.each(
    unrest: Types.Unrest,
    required: { string },
    onReady: (string, Parts) -> (),
    optional: { string }?
): ()
    local roles = table.clone(required)
    if optional ~= nil then
        for _, role in optional do
            table.insert(roles, role)
        end
    end
    local found: { [string]: Parts } = {}
    local done: { [string]: boolean } = {}

    --[[
        Only the player's own screens count.

        A tagged screen exists twice while the game runs: the template in `StarterGui` and the
        copy in `PlayerGui`. Both are in the DataModel, both carry the tag, and both are adopted
        -- so a query on a role returns two of everything, and two sliders read as four.

        Worse, the two copies share a group name, so whichever arrives first claims the group
        and the other is ignored. If that is the template, the player's own slider never wires
        up and nothing at all appears to happen.
    ]]
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local function mine(element: Instance): boolean
        return element:IsDescendantOf(playerGui)
    end

    local function complete(group: string): boolean
        local parts = found[group]
        for _, role in required do
            if parts[role] == nil then
                return false
            end
        end
        return true
    end

    for _, role in roles do
        unrest:Query({ Tag = unrest.Tag, Role = role }, {
            Added = function(element: Instance)
                if not mine(element) then
                    return
                end

                local group = Selector.groupOf(element)
                if group == nil then
                    warn(`[Widget] {element:GetFullName()} plays "{role}" but has no UnrestGroup.`)
                    return
                end

                local parts = found[group]
                if parts == nil then
                    parts = {}
                    found[group] = parts
                end
                parts[role] = element

                if not done[group] and complete(group) then
                    done[group] = true
                    onReady(group, parts)
                end
            end,
        })
    end
end

--[[
    Turns pressing `handle` into a stream of 0..1 positions along `track`, ending when the
    pointer is released anywhere on screen.

    `onMove` fires continuously while dragging. `onCommit`, if given, fires once when the
    pointer is released, with the position it was released at.

    The two are separate on purpose. A volume slider wants every move, because the player is
    listening while they drag. A slider that costs something -- a seek that reloads, a request
    that hits the server -- wants only the value the player settled on.

    Returns a function that stops listening, for a caller that needs to tear one down early.
]]
function Widget.drag(
    unrest: Types.Unrest,
    handle: Instance,
    track: GuiObject,
    onMove: (number) -> (),
    onCommit: ((number) -> ())?
): () -> ()
    local scope = Scythe.scope()

    local function fractionAt(x: number): number
        return math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
    end

    local function pointer(input: InputObject): boolean
        return input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
    end

    local function released(input: InputObject): boolean
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end

    local query = unrest:Query({ Tag = unrest.Tag, Selector = "GuiButton", Ancestor = track }, {
        Press = function(pressed: Instance)
            if pressed ~= handle then
                return
            end
            local handleGui = handle :: GuiObject

            Scythe.clean(scope)
            local latest = fractionAt(handleGui.AbsolutePosition.X + handleGui.AbsoluteSize.X / 2)

            Scythe.add(
                scope,
                UserInputService.InputChanged:Connect(function(input: InputObject)
                    if pointer(input) then
                        latest = fractionAt(input.Position.X)
                        onMove(latest)
                    end
                end)
            )
            Scythe.add(
                scope,
                UserInputService.InputEnded:Connect(function(input: InputObject)
                    if released(input) then
                        Scythe.clean(scope)
                        if onCommit ~= nil then
                            onCommit(latest)
                        end
                    end
                end)
            )
        end,
    })

    return function()
        Scythe.clean(scope)
        query:Destroy()
    end
end

return Widget
