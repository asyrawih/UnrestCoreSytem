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
    The rows: one per live server, drawn from a template a designer built.

        ServerList packet  -->  Bridge channel  -->  one clone per server in every list
        a row is clicked   -->  "ServerList.Selected" = that row's JobId

    THE TEMPLATE IS NOT BUILT HERE, AND THAT IS THE POINT. `CONVENTIONS.md` is blunt about it:
    UI is authored in Studio, in the place file, and never in `src/`. So this file contains no
    `Instance.new`, no sizes, no colours and no layout. It clones what a designer made, fills
    the labels that designer marked with a role, and parents the result. Restyle a row by
    editing the template; this file does not need to know.

    A ROW IS AN ORDINARY ADOPTED ELEMENT. The clone carries no tag of its own -- it does not
    need one. `List` sits under a tagged root, so the root's single `DescendantAdded` adopts
    the clone and every `GuiObject` inside it the moment it is parented. That is why the
    attributes are written BEFORE the parent is set: an element that arrives already carrying
    its group is wired once, whereas one that arrives bare and is edited afterwards is wired,
    torn down and wired again.

    WHY THE PRESS IS `Activated` AND NOT A QUERY. A query on the select button's role would
    match every row on screen and then need a `pressed ~= button` guard to throw away the
    other rows' presses -- one query and one set of watchers per row, to learn something this
    file is already holding, because it made the row. `Activated` is the same event the
    framework's own `Active` handler binds to, minus the search. `Toggle` in the examples
    reaches the same conclusion for the same reason.

    WHY SELECTING DOES NOT REDRAW. A redraw destroys every row, including the one whose button
    is halfway through the click being handled. Selection only changes one thing a row shows,
    so it repaints the outlines instead and leaves the instances alone. That also keeps the
    scroll position, which a rebuild would throw away on every click.

    WHY THE TEMPLATE CARRIES `UnrestIgnore`. It lives inside the list it is a template for, so
    without it the cascade would adopt it and every query for a row would match the cetakan as
    well as the rows -- a phantom server that is always present and never real. `UnrestIgnore`
    opts it and its labels back out; clearing that attribute on the clone is what switches a
    row on. The docs call this out as the legitimate use of the flag, and it is why the
    template must NOT be tagged itself: a tag beats `UnrestIgnore`, and a tagged-and-ignored
    instance manages itself anyway.

    WHY EVERY ROW IS DESTROYED WHEN THE DIRECTORY CHANGES. A directory is small -- `PAGE` is
    fifty -- and a server list changes wholesale rather than by increments: servers appear,
    fill, empty and die between two polls. Diffing fifty rows to save fifty `:Destroy()` calls
    every fifteen seconds would buy nothing and cost a reconciliation bug.

    WHY THE CLIENT ASKS. The server broadcasts on its own clock, so a client that just joined
    could sit in front of an empty panel for the better part of a poll interval. One request
    on load and one per Refresh press closes that window, and both are answered out of a cache
    that never reaches MemoryStore.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Channels = require(script.Parent.Channels)
local Constants = require(ReplicatedStorage.Unrest.Constants)
local GameNet = require(ReplicatedStorage:WaitForChild("GameNet"))
local Roles = require(script.Parent.Roles)
local Types = require(ReplicatedStorage.Unrest.Types)

local ATTRIBUTES = Constants.Attributes

--- One server as the `ServerList` packet carries it.
export type Entry = {
    JobId: string,
    Players: number,
    Capacity: number,
    Users: { number },
}

--[[
    How much of a JobId a row shows. It is a GUID: unreadable in full, and unique enough in
    its first segment for a player comparing two rows on one screen.
]]
local ID_CHARS = 8

--- Beyond this many ids a row says "and N more" rather than growing without limit.
local USERS_SHOWN = 12

--- How opaque a selected row's outline is. The unselected value is whatever the designer set
--- on the template, read once, so this file picks one colour and borrows the other.
local SELECTED_STROKE = 0

--- One drawn row, kept only for what repainting the selection would otherwise search for.
type Row = {
    JobId: string,
    Stroke: UIStroke?,
}

--- What one adopted `ServerListItems` list needs to redraw itself.
type List = {
    Instance: Instance,
    --- The designer's row, found once. Never parented anywhere and never modified.
    Template: GuiObject,
    --- Holds the current rows. Cleaned -- and so destroyed -- on every redraw.
    Scope: Types.Scope,
    Rows: { Row },
    --- The template's own outline transparency, which is what an unselected row wears.
    Idle: number,
    --- Optional. The line above the list that says how many servers there are.
    Status: TextLabel?,
}

local function shortId(jobId: string): string
    if #jobId <= ID_CHARS then
        return jobId
    end
    return string.sub(jobId, 1, ID_CHARS)
end

local function describeUsers(users: { number }): string
    if #users == 0 then
        return "no players"
    end

    local shown: { string } = {}
    for index = 1, math.min(#users, USERS_SHOWN) do
        table.insert(shown, tostring(users[index]))
    end

    local text = table.concat(shown, ", ")
    if #users > USERS_SHOWN then
        return `{text} and {#users - USERS_SHOWN} more`
    end
    return text
end

--[[
    Everything below arrived over the wire. The packet schema guarantees the fields decoded,
    not that they mean anything, and a malformed entry drawn as a row would be a row nobody
    can explain.
]]
local function accept(value: any): { Entry }
    if typeof(value) ~= "table" then
        return {}
    end

    local entries: { Entry } = {}
    for _, item in value do
        if typeof(item) ~= "table" or typeof(item.JobId) ~= "string" or item.JobId == "" then
            continue
        end

        local users: { number } = {}
        if typeof(item.Users) == "table" then
            for _, userId in item.Users do
                if typeof(userId) == "number" then
                    table.insert(users, userId)
                end
            end
        end

        table.insert(entries, {
            JobId = item.JobId,
            Players = if typeof(item.Players) == "number" then item.Players else #users,
            Capacity = if typeof(item.Capacity) == "number" then item.Capacity else 0,
            Users = users,
        })
    end

    return entries
end

return function(unrest: Types.Unrest, playerGui: Instance): Types.Cleanup
    local bridge = unrest.Bridge
    local Scope = unrest.Scope

    local lifetime = Scope.scope()
    local lists: { [Instance]: List } = {}

    --- Empty in Studio, which is exactly the case where every row is this server anyway.
    local here = game.JobId

    local function fill(row: GuiObject, entry: Entry): ()
        local name = Roles.find(row, "ServerListItemName")
        if name ~= nil and name:IsA("TextLabel") then
            local mine = entry.JobId == here and here ~= ""
            name.Text = if mine then `{shortId(entry.JobId)} (this server)` else shortId(entry.JobId)
        end

        local count = Roles.find(row, "ServerListItemCount")
        if count ~= nil and count:IsA("TextLabel") then
            count.Text = `{entry.Players} / {entry.Capacity}`
        end

        local users = Roles.find(row, "ServerListItemUsers")
        if users ~= nil and users:IsA("TextLabel") then
            users.Text = describeUsers(entry.Users)
        end
    end

    --- Outlines only. Cheap enough to run on every click, and it touches no instance's life.
    local function paint(list: List): ()
        local selected = bridge:Peek(Channels.Selected)
        for _, row in list.Rows do
            local stroke = row.Stroke
            if stroke ~= nil then
                stroke.Transparency = if row.JobId == selected then SELECTED_STROKE else list.Idle
            end
        end
    end

    local function draw(list: List): ()
        --- Destroys every row from the last draw, and with them the press each one carried.
        --- The template is not in here.
        Scope.clean(list.Scope)
        list.Rows = {}

        local entries = accept(bridge:Peek(Channels.Servers))

        for index, entry in entries do
            local clone = list.Template:Clone()
            clone.Name = "ServerListItem"
            clone.LayoutOrder = index
            clone.Visible = true

            --[[
                Written before the parent, so the element is adopted already knowing what it
                is. `UnrestIgnore` has to go or the clone would be opted out exactly like the
                template it came from; `UnrestGroup` is what lets a designer wire something
                per row in Studio and have it mean this row rather than all of them.
            ]]
            clone:SetAttribute(ATTRIBUTES.Ignore, nil)
            clone:SetAttribute(ATTRIBUTES.Role, "ServerListItem")
            clone:SetAttribute(ATTRIBUTES.Group, entry.JobId)

            fill(clone, entry)

            --- Owned before it is shown: a draw that threw between the clone and the parent
            --- would leave an instance on screen that no later redraw knows to remove.
            local row = Scope.add(list.Scope, clone)
            row.Parent = list.Instance

            local stroke = Roles.find(row, "ServerListItemStroke")
            local record: Row = {
                JobId = entry.JobId,
                Stroke = if stroke ~= nil and stroke:IsA("UIStroke") then stroke else nil,
            }
            table.insert(list.Rows, record)

            --[[
                The press goes in AFTER the row, so LIFO disconnects it before the instance it
                belongs to is destroyed. Without that ordering a redraw could destroy a row
                whose click was still on the stack.
            ]]
            local select = Roles.find(row, "ServerListItemSelect")
            if select ~= nil and select:IsA("GuiButton") then
                local jobId = entry.JobId
                Scope.add(
                    list.Scope,
                    select.Activated:Connect(function()
                        bridge:Publish(Channels.Selected, jobId)
                    end)
                )
            end
        end

        local status = list.Status
        if status ~= nil then
            status.Text = if #entries == 0
                then "no servers yet"
                elseif #entries == 1 then "1 server"
                else `{#entries} servers`
        end

        paint(list)
    end

    local items = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiObject",
        Role = "ServerListItems",
        Ancestor = playerGui,
    }, {
        Added = function(element: Instance)
            local template = Roles.find(element, "ServerListItemTemplate")
            if template == nil or not template:IsA("GuiObject") then
                --[[
                    Loud, not fatal. An empty list is a screen a designer can still use; a
                    thrown error takes the whole feature with it, and the cause is one missing
                    attribute in Studio rather than anything this file can fix.
                ]]
                warn(
                    `[ServerList] {element:GetFullName()} is a ServerListItems list with no row `
                        .. `template under it. Set {ATTRIBUTES.Role} = "ServerListItemTemplate" on the `
                        .. `frame the rows are cloned from, and {ATTRIBUTES.Ignore} = true so it is not `
                        .. `itself drawn as a row.`
                )
                return
            end

            --- The status line is a sibling of the list rather than a child of it, so the
            --- search for it has to start from the panel that owns both.
            local status = Roles.find(Roles.owner(element, "ServerListPanel"), "ServerListStatus")

            local idle = Roles.find(template, "ServerListItemStroke")

            local list: List = {
                Instance = element,
                Template = template,
                Scope = Scope.scope(),
                Rows = {},
                Idle = if idle ~= nil and idle:IsA("UIStroke") then idle.Transparency else 0.65,
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
            Scope.destroy(list.Scope)
        end,
    })

    local refresh = unrest:Query({
        Tag = unrest.Tag,
        Selector = "GuiButton",
        Role = "ServerListRefresh",
        Ancestor = playerGui,
    }, {
        Active = function(): ()
            --- Answered from the server's cache, so this is a buffer and nothing more.
            GameNet.packets.ServerListRequest.send(nil)
        end,
    })

    Scope.addBulk(
        lifetime,
        refresh,
        items,
        --[[
            Every published directory redraws every list. `Subscribe` replays the current value
            on its own, after this line returns, so a list adopted before the first packet and
            one adopted after it both start correct.
        ]]
        bridge:Subscribe(Channels.Servers, function()
            for _, list in lists do
                draw(list)
            end
        end),
        --- A selection changes one thing a row shows and nothing about which rows exist.
        bridge:Subscribe(Channels.Selected, function()
            for _, list in lists do
                paint(list)
            end
        end)
    )

    --[[
        Packet to channel, which is the only place this direction is spelled. The server never
        names a channel: it sends a `ServerList` and the client decides what that means, which
        is what keeps the server from ordering the UI around.
    ]]
    GameNet.packets.ServerList.listen(function(data)
        if typeof(data) ~= "table" then
            return
        end
        bridge:Publish(Channels.Servers, data.Servers)
    end)

    --- Ask once, rather than waiting out the server's own clock for the first list.
    GameNet.packets.ServerListRequest.send(nil)

    return function(): ()
        Scope.destroy(lifetime)
        for element, list in lists do
            lists[element] = nil
            Scope.destroy(list.Scope)
        end
    end
end
