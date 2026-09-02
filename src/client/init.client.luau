--!strict
--[[
    UnrestClient -- StarterPlayer.StarterPlayerScripts.UnrestClient

    Client bootstrap, and the framework's own worked example of the only workflow it has.

    There is no UI in this file. There is no UI anywhere in the framework. Every element
    this script talks to was built by hand in Studio and opted in with one CollectionService
    tag, `Unrest`. If nothing is tagged, nothing happens, and the script says so clearly
    rather than manufacturing a demo screen to have something to point at -- building UI is
    precisely the job the framework does not do.

    It shows both halves of adoption:

      1. attribute-only wiring, which needs no code at all. A designer sets `UnrestCommand`
         on a button and `UnrestChannel` / `UnrestBind` / `UnrestFormat` on a label, and the
         ElementManager wires them on adoption. This script only *reports* what got wired.
      2. code-driven `Unrest:Query`, for behaviour an attribute cannot express -- reading a
         channel before dispatching, say, or reacting to hover.

    To try it, in Studio:

        * build a ScreenGui with a TextButton and a TextLabel in StarterGui;
        * tag both `Unrest` (Studio's Tag Editor, or CollectionService:AddTag);
        * on the button set  UnrestRole = "ToggleMenu"  and  UnrestGroup = "MainMenu";
        * on the label  set  UnrestChannel = "Music.NowPlaying",
                             UnrestBind    = "Text",
                             UnrestFormat  = "Music: {value}".

    The button then dispatches through the Bridge with no code, the label follows framework
    state with no code, and the query below adds the extra behaviour on top.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Unrest")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Types = require(ReplicatedStorage.Unrest.Types)
local Unrest = require(ReplicatedStorage.Unrest)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--- How long to wait for StarterGui to replicate before concluding nothing is tagged.
local ADOPTION_GRACE = 5

--------------------------------------------------------------------------------
-- 1. Watch adoption before starting, so the initial sweep is visible too.
--------------------------------------------------------------------------------

--[[
    `ManagedAdded` fires for elements that were already tagged when `Start` ran *and* for
    every element tagged afterwards, so connecting first means one handler covers both. The
    listing is a debug aid: it prints exactly what the framework read off each element, so a
    designer can tell the difference between "my attribute is wrong" and "my tag is missing".
]]
local function describeAttributes(element: Types.ManagedElement): string
    local parts: { string } = {}
    for _, name in { "Command", "Payload", "Channel", "Bind", "Format", "Cooldown" } do
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

Unrest.Elements.ManagedAdded:Connect(function(element: Types.ManagedElement)
    local group = if element.Group ~= nil then ` group "{element.Group}"` else ""
    print(
        `[UnrestClient] adopted {element.Instance:GetFullName()} `
            .. `[{element.Instance.ClassName} -> {element.Adapter.ClassName}] `
            .. `role "{element.Role}"{group}: {describeAttributes(element)}`
    )
end)

Unrest.Elements.ManagedRemoved:Connect(function(element: Types.ManagedElement)
    print(`[UnrestClient] released {element.Instance.Name} (role "{element.Role}")`)
end)

local unrest = Unrest:Start()

--------------------------------------------------------------------------------
-- 2. Degrade loudly, and only once, when there is nothing to manage.
--------------------------------------------------------------------------------

--[[
    StarterGui is copied into PlayerGui asynchronously, so "no elements yet" at this instant
    means nothing. Give replication a few seconds before saying anything, and stay quiet if
    an element shows up in the meantime.
]]
task.delay(ADOPTION_GRACE, function()
    if #unrest.Elements:All() > 0 then
        return
    end

    warn(
        `[UnrestClient] no instance is tagged "{Constants.Tag}", so the framework is managing nothing.\n`
            .. `  Unrest builds no UI on purpose -- it adopts UI you built in Studio.\n`
            .. `  Add the tag to an existing GuiObject (Studio: View > Tag Editor, or\n`
            .. `  CollectionService:AddTag(instance, "{Constants.Tag}")) and it will be adopted live,\n`
            .. `  with no restart and no change to this script.\n`
            .. `  Searched: every tagged instance in the DataModel, including {playerGui:GetFullName()}.`
    )
end)

--------------------------------------------------------------------------------
-- 3. Code-driven binding: the whiteboard sketch, registered before anything matches.
--------------------------------------------------------------------------------

--[[
    Selecting on `Role` rather than `Name` is the point. `UnrestRole` is a contract the
    designer sets deliberately; `Name` is what changes the afternoon after you ship. When
    the attribute is absent, `Role` falls back to the name, so a button simply called
    "ToggleMenu" matches this query too.

    This query is created before its element is guaranteed to exist. That is the normal
    case, not a trick: the binding is live, so a matching element tagged in ten minutes'
    time is bound in ten minutes' time.
]]
local toggle = unrest:Query({
    Tag = Constants.Tag,
    Selector = "GuiButton", -- is:A("GuiButton") -- TextButton and ImageButton both
    Role = "ToggleMenu",
}, {
    Added = function(element: Instance)
        print(`[UnrestClient] query matched {element:GetFullName()}`)
    end,

    Active = function(element: Instance)
        --[[
            Behaviour an attribute cannot express: read the current state first, then decide
            which command to send. An `UnrestCommand` attribute is one fixed command; this is
            the escape hatch for when that is not enough.
        ]]
        local playing = unrest.Bridge:Peek(Constants.Channels.NowPlaying)
        if playing == nil then
            unrest:Dispatch(Constants.Commands.MusicPlay, "Lobby")
        else
            unrest:Dispatch(Constants.Commands.MusicStop, nil)
        end
        print(`[UnrestClient] activated {element.Name}`)
    end,

    Hover = function(element: Instance)
        print(`[UnrestClient] hovering {element.Name}`)
    end,

    Unhover = function(element: Instance)
        print(`[UnrestClient] left {element.Name}`)
    end,

    Removed = function(element: Instance)
        print(`[UnrestClient] {element.Name} stopped matching`)
    end,
})

--[[
    `Group` selects a whole screen's worth of elements without naming any of them, which is
    what makes "hide the main menu" one line instead of a list of references. Nothing is
    bound here -- a bare query is still a live, countable set.
]]
local mainMenu = unrest:Query({
    Tag = Constants.Tag,
    Group = "MainMenu",
})

mainMenu.ElementAdded:Connect(function(element: Instance)
    print(`[UnrestClient] MainMenu now has {mainMenu:Count()} element(s), latest {element.Name}`)
end)

--------------------------------------------------------------------------------
-- 4. Core -> UI. Retained, so subscribing after the fact still paints correctly.
--------------------------------------------------------------------------------

--[[
    A label with `UnrestChannel` + `UnrestBind` already does this with no code. This
    subscription is the same data arriving somewhere an attribute cannot reach -- a print,
    a sound, a camera move.
]]
unrest.Bridge:Subscribe(Constants.Channels.NowPlaying, function(value: any)
    print(`[UnrestClient] now playing: {if value == nil then "nothing" else tostring(value)}`)
end)

--- Refusals are a programming error on the client side, so surface them rather than swallow.
unrest.Bridge.Rejected:Connect(function(rejection: Types.Rejection)
    warn(`[UnrestClient] "{rejection.Command}" refused ({rejection.Reason}): {rejection.Detail}`)
end)

print(
    `[UnrestClient] Unrest {unrest.Version} ready -- `
        .. `{#unrest.Elements:All()} element(s) adopted, `
        .. `{toggle:Count()} matching the ToggleMenu query, `
        .. `systems: {table.concat(unrest.Core:List(), ", ")}`
)
