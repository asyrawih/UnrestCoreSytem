--!strict
--[[
    UnrestClient / Diagnostics

    Everything the bootstrap used to print, moved here so the bootstrap can be read in one
    screen. This is a wiring aid, not part of the framework: it answers the two questions you
    actually have while building a screen.

      * Did the framework see my element, and what did it read off it? Every adoption prints
        the class, the adapter that claimed it, the role, the group, and the wiring
        attributes as *resolved* -- so a value arriving from a preset or inherited from the
        ScreenGui shows up here even though the element itself carries nothing.
      * Is anything tagged at all? If nothing is adopted shortly after start, it says so, at
        length, because the alternative is a silent screen and no idea why.

    Usage, one line in the bootstrap:

        require(script.Diagnostics)(unrest)

    Delete that line when the screen works. Nothing else depends on this module.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Types = require(ReplicatedStorage.Unrest.Types)

--[[
    StarterGui is copied into PlayerGui asynchronously, so "nothing adopted yet" measured at
    the instant of start means nothing at all. Wait a few seconds before drawing a conclusion.
]]
local ADOPTION_GRACE = 5

--- The wiring attributes, in the order a reader wants to see them.
local WIRING = { "Preset", "Command", "Payload", "Channel", "Bind", "Format", "Cooldown" }

--[[
    Reports the resolved attributes, not the raw ones. The difference is the whole point:
    an element with `UnrestPreset = "MusicToggle"` and nothing else still prints the command
    and the format it resolved to, so "my attribute is wrong" and "my tag is missing" stop
    looking identical from the output window.
]]
local function describeAttributes(element: Types.ManagedElement): string
    local parts: { string } = {}

    for _, name in WIRING do
        local attribute = (Constants.Attributes :: { [string]: string })[name]
        local value = element.Attributes[attribute]
        if value ~= nil then
            table.insert(parts, `{attribute} = {tostring(value)}`)
        end
    end

    if #parts == 0 then
        return "no wiring attributes -- adopted and queryable, nothing more"
    end
    return table.concat(parts, ", ")
end

--[[
    Connects the listeners, then reports what is already there.

    `ManagedAdded` fires both for elements tagged before `Start` ran and for every element
    tagged afterwards, so a single handler covers the initial sweep and everything later --
    but only if it is connected first. Calling this after `Start` would miss the sweep, so
    the already-adopted set is replayed here rather than assumed empty.
]]
return function(unrest: Types.Unrest): () -> ()
    local function report(element: Types.ManagedElement): ()
        local group = if element.Group ~= nil then ` group "{element.Group}"` else ""
        print(
            `[Unrest] adopted {element.Instance:GetFullName()} `
                .. `[{element.Instance.ClassName} -> {element.Adapter.ClassName}] `
                .. `role "{element.Role}"{group}: {describeAttributes(element)}`
        )
    end

    local added = unrest.Elements.ManagedAdded:Connect(report)
    local removed = unrest.Elements.ManagedRemoved:Connect(function(element: Types.ManagedElement)
        print(`[Unrest] released {element.Instance.Name} (role "{element.Role}")`)
    end)

    for _, element in unrest.Elements:All() do
        report(element)
    end

    task.delay(ADOPTION_GRACE, function()
        if #unrest.Elements:All() > 0 then
            return
        end

        local player = Players.LocalPlayer
        local playerGui = if player ~= nil then player:FindFirstChildOfClass("PlayerGui") else nil
        local where = if playerGui ~= nil then playerGui:GetFullName() else "the player's PlayerGui"

        warn(
            `[Unrest] no instance is tagged "{Constants.Tag}", so the framework is managing nothing.\n`
                .. `  Unrest builds no UI on purpose -- it adopts UI you built in Studio.\n`
                .. `  Add the tag to an existing GuiObject (Studio: View > Tag Editor, or\n`
                .. `  CollectionService:AddTag(instance, "{Constants.Tag}")) and it will be adopted live,\n`
                .. `  with no restart and no change to your bootstrap.\n`
                .. `  Searched: every tagged instance in the DataModel, including {where}.`
        )
    end)

    --- Stops the reporting. Rarely needed: deleting the require is the usual way.
    return function()
        added:Disconnect()
        removed:Disconnect()
    end
end
