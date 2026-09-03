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
    The side panel: who is in the server the player picked.

        a row is clicked  -->  "ServerList.Selected" = JobId  -->  this panel grows out and
                                                                   draws one circle per player

    The panel is driven by the same kind of boolean the list is, derived rather than stored:
    a selection that is not the empty string means open. There is no second "is the side panel
    showing" state to keep in step with the selection, because there is nothing a second state
    could say that the first does not.

    WHY IT GROWS INSTEAD OF SLIDING. `ServerListContainer` carries a horizontal `UIListLayout`,
    so the panel's `Position` is not its own -- the layout rewrites it every time anything in
    the row changes size. Tweening `Size.X` from zero is the one move that works WITH that
    layout instead of against it: the list beside it slides over as this one opens, which is
    the effect anyway. `ClipsDescendants` is on for the same reason, or the contents would
    spill out of a panel that is one pixel wide.

    CONNECTIONS ARE FETCHED ONCE, NOT PER PLAYER. `Player:IsFriendsWith` is a yielding web
    call, and asking it per avatar means sixty of them for a full server, every redraw, at a
    rate limit that will refuse most of them. `Players:GetFriendsAsync` answers the same
    question for everybody in one paged call, so it runs once, on a thread of its own, and
    every draw after that reads a table. A server list that redraws every fifteen seconds
    cannot afford anything else.

    WHY `rbxthumb://` AND NOT `GetUserThumbnailAsync`. The Async one yields, and a draw runs
    inside `Bridge:Publish` -- which calls its subscribers inline, so a yield there holds up
    the publish and everything else subscribed to it. `rbxthumb://` is a plain image URL the
    engine resolves on its own, so a draw stays synchronous.

    What Studio needs, under `SidePanelServer`:

        UnrestRole "ServerInfoPanel"   on the panel, and ClipsDescendants ticked
        UnrestRole "ServerInfoItems"   on its ScrollingFrame
        UnrestRole "ServerInfoConnections" / "ServerInfoOthers"  on the two grid frames
        UnrestRole "ServerInfoDivider" on the line between them
        UnrestRole "ServerInfoItemTemplate" + UnrestIgnore on the cell it clones
        UnrestRole "ServerInfoItemAvatar" / "ServerInfoItemRing" inside that cell
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Channels = require(script.Parent.Channels)
local Constants = require(ReplicatedStorage.Unrest.Constants)
local RevealFactory = require(script.Parent.Reveal)
local Roles = require(script.Parent.Roles)
local Types = require(ReplicatedStorage.Unrest.Types)

local ATTRIBUTES = Constants.Attributes

--- Faster than the list, because this panel opens in answer to a click rather than a decision.
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

--- Headshot size to ask the thumbnail service for. Cells are 52px, so 150 is already generous.
local THUMB = 150

--[[
    A ceiling on the friend-list walk. `GetFriendsAsync` pages, and a loop over a paged API
    with no bound is a loop that hangs the thread it runs on the day the API misbehaves.
]]
local MAX_PAGES = 10

--- One adopted `ServerInfoItems` list and the parts of its panel it draws into.
type List = {
    Instance: Instance,
    --- The designer's cell. Never parented anywhere and never modified.
    Template: GuiObject,
    --- Holds the current cells. Cleaned -- and so destroyed -- on every redraw.
    Cells: Types.Scope,
    Connections: GuiObject?,
    Others: GuiObject?,
    Divider: GuiObject?,
    Status: TextLabel?,
}

local function headshot(userId: number): string
    return `rbxthumb://type=AvatarHeadShot&id={userId}&w={THUMB}&h={THUMB}`
end

local function plural(count: number, one: string, many: string): string
    return if count == 1 then `{count} {one}` else `{count} {many}`
end

return function(unrest: Types.Unrest, playerGui: Instance): Types.Cleanup
    local bridge = unrest.Bridge
    local Scope = unrest.Scope

    local lifetime = Scope.scope()
    local lists: { [Instance]: List } = {}

    --[[
        Empty until the fetch below finishes, and that is a state rather than a failure: the
        panel draws everybody as an ordinary player, and redraws once the answer arrives.
    ]]
    local connections: { [number]: true } = {}

    local reveal = RevealFactory(Scope, {
        Property = "Size",
        Hide = function(resting: any): any
            local size = resting :: UDim2
            return UDim2.new(0, 0, size.Y.Scale, size.Y.Offset)
        end,
        Open = OPEN,
        Close = CLOSE,
    })

    --- The entry the player picked, or nil when nothing is picked or it has since gone away.
    local function selected(): any
        local jobId = bridge:Peek(Channels.Selected)
        if typeof(jobId) ~= "string" or jobId == "" then
            return nil
        end

        local servers = bridge:Peek(Channels.Servers)
        if typeof(servers) ~= "table" then
            return nil
        end

        for _, entry in servers do
            if typeof(entry) == "table" and entry.JobId == jobId then
                return entry
            end
        end
        return nil
    end

    --- One cell, made and filled but NOT parented: where it goes is the caller's decision.
    local function cell(list: List, userId: number, connected: boolean): GuiObject
        local clone = list.Template:Clone()
        clone.Name = "ServerInfoItem"
        clone.Visible = true
        --- Ascending user id, so a redraw of the same server puts the same faces in the same
        --- places rather than reshuffling them under the player's cursor.
        clone.LayoutOrder = userId

        --[[
            Written before the parent, so the element is adopted already knowing what it is.
            `UnrestIgnore` has to go or the clone would be opted out exactly like the template
            it came from.
        ]]
        clone:SetAttribute(ATTRIBUTES.Ignore, nil)
        clone:SetAttribute(ATTRIBUTES.Role, "ServerInfoItem")
        clone:SetAttribute(ATTRIBUTES.Group, tostring(userId))

        local avatar = Roles.find(clone, "ServerInfoItemAvatar")
        if avatar ~= nil and avatar:IsA("ImageLabel") then
            avatar.Image = headshot(userId)
        end

        --- The ring is the whole difference a connection makes to a cell. It is off in the
        --- template, so an ordinary player needs no decision taken about them at all.
        local ring = Roles.find(clone, "ServerInfoItemRing")
        if ring ~= nil and ring:IsA("UIStroke") then
            ring.Enabled = connected
        end

        return clone
    end

    local function draw(list: List): ()
        --- Destroys every cell from the last draw. The template is not in here.
        Scope.clean(list.Cells)

        local entry = selected()
        local users: { number } = if entry ~= nil and typeof(entry.Users) == "table" then entry.Users else {}

        local friends = 0
        local others = 0

        for _, userId in users do
            if typeof(userId) ~= "number" then
                continue
            end

            local connected = connections[userId] == true
            local section = if connected then list.Connections else list.Others
            if section == nil then
                continue
            end

            --[[
                Owned before it is shown. A draw that threw between the clone and the parent
                would otherwise leave an instance nobody holds -- and one that is already on
                screen is the single kind of leak a redraw cannot clear, because the next
                redraw only knows about what its own scope is holding.

                The SECTION is never added here. It is the designer's frame, and a scope that
                held it would destroy the panel's own furniture on the first redraw.
            ]]
            local clone = Scope.add(list.Cells, cell(list, userId, connected))
            clone.Parent = section

            if connected then
                friends += 1
            else
                others += 1
            end
        end

        if list.Connections ~= nil then
            (list.Connections :: GuiObject).Visible = friends > 0
        end
        if list.Others ~= nil then
            (list.Others :: GuiObject).Visible = others > 0
        end

        --- The line only means something when there is something on both sides of it.
        if list.Divider ~= nil then
            (list.Divider :: GuiObject).Visible = friends > 0 and others > 0
        end

        local status = list.Status
        if status ~= nil then
            if entry == nil then
                status.Text = "pick a server"
            elseif friends > 0 then
                status.Text =
                    `{plural(friends + others, "player", "players")} - {plural(friends, "connection", "connections")}`
            else
                status.Text = plural(friends + others, "player", "players")
            end
        end
    end

    local function redraw(): ()
        for _, list in lists do
            draw(list)
        end
    end

    local panels = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiObject",
        Role = "ServerInfoPanel",
        Ancestor = playerGui,
    }, {
        Added = function(element: Instance)
            local jobId = bridge:Peek(Channels.Selected)
            reveal:Adopt(element :: GuiObject, typeof(jobId) == "string" and jobId ~= "")
        end,

        Removed = function(element: Instance)
            reveal:Release(element :: GuiObject)
        end,
    })

    local items = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiObject",
        Role = "ServerInfoItems",
        Ancestor = playerGui,
    }, {
        Added = function(element: Instance)
            local template = Roles.find(element, "ServerInfoItemTemplate")
            if template == nil or not template:IsA("GuiObject") then
                --[[
                    Loud, not fatal. An empty panel is a screen a designer can still use; a
                    thrown error takes the whole feature with it, and the cause is one missing
                    attribute in Studio rather than anything this file can fix.
                ]]
                warn(
                    `[ServerList] {element:GetFullName()} is a ServerInfoItems list with no cell `
                        .. `template under it. Set {ATTRIBUTES.Role} = "ServerInfoItemTemplate" on the `
                        .. `frame the avatars are cloned from, and {ATTRIBUTES.Ignore} = true so it is `
                        .. `not itself drawn as one.`
                )
                return
            end

            --- The status line is a sibling of the list rather than a child of it, so the
            --- search for it has to start from the panel that owns both.
            local panel = Roles.owner(element, "ServerInfoPanel")
            local status = Roles.find(panel, "ServerInfoStatus")

            local connectionsSection = Roles.find(element, "ServerInfoConnections")
            local othersSection = Roles.find(element, "ServerInfoOthers")
            local divider = Roles.find(element, "ServerInfoDivider")

            local list: List = {
                Instance = element,
                Template = template,
                Cells = Scope.scope(),
                Connections = if connectionsSection ~= nil and connectionsSection:IsA("GuiObject")
                    then connectionsSection
                    else nil,
                Others = if othersSection ~= nil and othersSection:IsA("GuiObject") then othersSection else nil,
                Divider = if divider ~= nil and divider:IsA("GuiObject") then divider else nil,
                Status = if status ~= nil and status:IsA("TextLabel") then status else nil,
            }
            lists[element] = list

            draw(list)
        end,

        Removed = function(element: Instance)
            local list = lists[element]
            if list == nil then
                return
            end
            lists[element] = nil
            --- Destroyed rather than cleaned: this list is not coming back, and the handle
            --- should go back to the pool with it.
            Scope.destroy(list.Cells)
        end,
    })

    local closers = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiButton",
        Role = "ServerInfoClose",
        Ancestor = playerGui,
    }, {
        --- Closing the side panel is deselecting. There is no second state to clear.
        Active = function(): ()
            bridge:Publish(Channels.Selected, "")
        end,
    })

    if bridge:Peek(Channels.Selected) == nil then
        bridge:Publish(Channels.Selected, "")
    end

    Scope.addBulk(
        lifetime,
        reveal,
        closers,
        items,
        panels,
        --[[
            One call, on a thread of its own because it yields, and its result changes how
            every already-drawn cell should look -- hence the redraw rather than a flag some
            later draw would have to remember to check.

            Not repeated. A connection made during a session will not get a ring until the
            player reopens the game, which is a smaller wrong answer than a paged web call on
            a timer.
        ]]
        task.spawn(function()
            local ok, pages = pcall(function()
                return Players:GetFriendsAsync(Players.LocalPlayer.UserId)
            end)

            if not ok then
                --- Studio without API access, or the service being unavailable. Everybody is
                --- drawn as an ordinary player, which is the honest answer to "I do not know".
                warn(`[ServerList] could not read connections: {pages}`)
                return
            end

            local page = pages :: FriendPages
            for _ = 1, MAX_PAGES do
                for _, friend in page:GetCurrentPage() do
                    if typeof(friend.Id) == "number" then
                        connections[friend.Id] = true
                    end
                end

                if page.IsFinished then
                    break
                end

                local advanced = pcall(function()
                    page:AdvanceToNextPageAsync()
                end)
                if not advanced then
                    break
                end
            end

            redraw()
        end),
        bridge:Subscribe(Channels.Servers, redraw),
        bridge:Subscribe(Channels.Selected, function(value: any)
            reveal:Apply(typeof(value) == "string" and value ~= "")
            redraw()
        end)
    )

    return function(): ()
        Scope.destroy(lifetime)
        for element, list in lists do
            lists[element] = nil
            Scope.destroy(list.Cells)
        end
    end
end
