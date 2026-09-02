--!strict
--[[
    Unrest / Bridge

    The controller column of the whiteboard. The single seam between the Model (Core) and
    the View (UI), and the reason neither has to know the other exists:

      * Core publishes state           -> `Bridge:Publish(channel, value)`
      * UI reads and follows state     -> `Bridge:Subscribe(channel, handler)` / `:Peek(channel)`
      * UI dispatches intent           -> `Bridge:Dispatch(command, payload)`
      * Core handles intent            -> `Bridge:OnCommand(command, handler)`
      * Anyone selects Instances       -> `Bridge:Query(descriptor, handlers)`

    Channels are *retained*: a late subscriber immediately receives the last published value,
    so a UI element that mounts after the music started still renders the right track. That
    is what makes the Bridge safe to use from components with arbitrary mount order.

    The Bridge is process-local. It does not replicate; a networked framework would put
    RemoteEvents behind a system, not behind the Bridge.
]]

local Maid = require(script.Maid)
local Query = require(script.Query)
local Signal = require(script.Signal)
local Types = require(script.Parent.Types)

type Channel = {
    Value: any,
    HasValue: boolean,
    Signal: Types.Signal<any>,
}

local Bridge = {}

function Bridge.new(): Types.Bridge
    local channels: { [string]: Channel } = {}
    local commands: { [string]: Types.Signal<any> } = {}
    local queries: { Types.QueryHandle } = {}
    local lifetime = Maid.new()
    local destroyed = false

    local bridge = {}

    local function assertAlive(method: string): ()
        if destroyed then
            error(`[Unrest.Bridge] :{method} called after the Bridge was destroyed.`, 0)
        end
    end

    local function assertName(value: any, method: string, label: string): string
        if typeof(value) ~= "string" or #value == 0 then
            error(`[Unrest.Bridge] :{method} expects a non-empty {label} name, got {typeof(value)}.`, 0)
        end
        return value :: string
    end

    local function channelFor(name: string): Channel
        local channel = channels[name]
        if channel == nil then
            local created: Channel = {
                Value = nil,
                HasValue = false,
                Signal = Signal.new(`Bridge.Channel[{name}]`),
            }
            channels[name] = created
            lifetime:Add(created.Signal)
            return created
        end
        return channel
    end

    local function commandFor(name: string): Types.Signal<any>
        local command = commands[name]
        if command == nil then
            local created: Types.Signal<any> = Signal.new(`Bridge.Command[{name}]`)
            commands[name] = created
            lifetime:Add(created)
            return created
        end
        return command
    end

    --- Core -> UI. The value is retained and replayed to future subscribers.
    function bridge:Publish(channel: string, value: any): ()
        assertAlive("Publish")
        local name = assertName(channel, "Publish", "channel")
        local entry = channelFor(name)
        entry.Value = value
        entry.HasValue = true
        entry.Signal:Fire(value)
    end

    --- UI -> Core. Subscribers receive the retained value immediately, then every update.
    function bridge:Subscribe(channel: string, handler: (value: any) -> ()): Types.Connection
        assertAlive("Subscribe")
        local name = assertName(channel, "Subscribe", "channel")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :Subscribe("{name}") expects a function, got {typeof(handler)}.`, 0)
        end

        local entry = channelFor(name)
        local connection = entry.Signal:Connect(handler)
        if entry.HasValue then
            local value = entry.Value
            task.spawn(function()
                if connection.Connected then
                    handler(value)
                end
            end)
        end

        return connection
    end

    function bridge:Peek(channel: string): any
        local name = assertName(channel, "Peek", "channel")
        local entry = channels[name]
        return if entry ~= nil then entry.Value else nil
    end

    --- UI -> Core intent. No return value: commands are requests, not queries.
    function bridge:Dispatch(command: string, payload: any): ()
        assertAlive("Dispatch")
        local name = assertName(command, "Dispatch", "command")
        commandFor(name):Fire(payload)
    end

    function bridge:OnCommand(command: string, handler: (payload: any) -> ()): Types.Connection
        assertAlive("OnCommand")
        local name = assertName(command, "OnCommand", "command")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :OnCommand("{name}") expects a function, got {typeof(handler)}.`, 0)
        end
        return commandFor(name):Connect(handler)
    end

    --- Live selector engine. Queries are owned by the Bridge and die with it.
    function bridge:Query(descriptor: Types.Descriptor, handlers: Types.Handlers?): Types.QueryHandle
        assertAlive("Query")
        local created = Query.new(descriptor, handlers)
        table.insert(queries, created)
        return created
    end

    function bridge:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        for _, query in queries do
            query:Destroy()
        end
        table.clear(queries)
        table.clear(channels)
        table.clear(commands)
        lifetime:Destroy()
    end

    return (bridge :: any) :: Types.Bridge
end

return Bridge
