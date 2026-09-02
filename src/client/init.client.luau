--!strict
--[[
    UnrestClient -- StarterPlayer.StarterPlayerScripts.UnrestClient

    Start the framework, then add only the wiring an attribute cannot express. In a shipping
    game this file stays about this size: the screens are built in Studio and most buttons
    are wired there with `Unrest*` attributes, so there is nothing for a script to say about
    them.

    Follow docs/GETTING-STARTED.md once and you will not need to read this again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Unrest").Constants)
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--[[
    Prints what the framework adopts and what it read off each element, and complains if
    nothing is tagged. Useful while wiring a screen, pointless afterwards -- delete this line
    when the screen works. Nothing else depends on it.
]]
require(script.Diagnostics)(unrest)

--[[
    The one thing an attribute cannot do: decide between two commands by reading current
    state. `UnrestCommand` is one fixed command, and this button is a toggle.

    `Role` falls back to `Instance.Name`, so a button simply named "ToggleMenu" matches with
    no attribute at all. The query is live: registering it before the button exists is the
    normal case, not a trick.
]]
unrest:Query({
    Tag = unrest.Tag,
    Selector = "GuiButton", -- is:A("GuiButton") -- TextButton and ImageButton both
    Role = "ToggleMenu",
}, {
    Active = function()
        if unrest.Bridge:Peek(Constants.Channels.NowPlaying) == nil then
            unrest:Dispatch(Constants.Commands.MusicPlay, "Lobby")
        else
            unrest:Dispatch(Constants.Commands.MusicStop, nil)
        end
    end,
})
