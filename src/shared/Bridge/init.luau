--!strict
--[[
    Unrest / Bridge

    The controller column of the whiteboard: a local bus, and the only thing that stands
    between the code that owns state and the Studio-built UI that shows it.

      * State goes out    -> `Bridge:Publish(channel, value)`
      * UI follows state  -> `Bridge:Subscribe(channel, handler)` / `:Peek(channel)`
      * UI sends intent   -> `Bridge:Dispatch(command, payload)`
      * Something acts    -> `Bridge:Handle(command, handler)`

    Two directions, four verbs, no wire. Everything here happens inside one Luau VM.

    CHANNELS ARE RETAINED, and that is a UI feature rather than a bookkeeping one. The last
    value published on a channel is kept, and a subscriber that arrives afterwards is handed
    it immediately. Without that, a label bound to `UnrestChannel` would render blank until
    the next publish -- so the correctness of a screen would depend on whether it happened to
    mount before or after the state it displays. With it, mount order stops mattering: a
    label is correct on its first frame no matter when it appeared.

    WHY THIS IS A SEPARATE OBJECT AT ALL, given how small it is. `Elements` adopts instances
    and knows nothing about where a value came from; the code that owns the value knows
    nothing about instances. The Bridge is the one name both sides can say. `UnrestCommand`
    goes out through `Dispatch` and `UnrestChannel` comes in through `Subscribe`, so a
    designer can wire a whole screen in Studio without either side learning about the other.

    A command with no handler is a no-op, deliberately and quietly. A screen is often built
    before the code behind it, and a button that does nothing yet should not warn on every
    click. What is NOT quiet is a handler that throws: it is caught, reported with its
    traceback, and the other handlers still run.
]]

local Scope = require(script.Parent.Util.Scope)
local Signal = require(script.Parent.Util.Signal)
local Types = require(script.Parent.Types)

type Channel = {
    Value: any,
    HasValue: boolean,
    Signal: Types.Signal<any>,
}

local Bridge = {}

function Bridge.new(context: Types.RuntimeContext): Types.Bridge
    if context ~= "Server" and context ~= "Client" then
        error(`[Unrest.Bridge] .new expects "Server" or "Client", got {tostring(context)}.`, 0)
    end

    local channels: { [string]: Channel } = {}
    local handlers: { [string]: { Types.CommandHandler } } = {}
    local lifetime = Scope.scope()
    local destroyed = false

    local bridge = {
        Context = context,
    }

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
            Scope.add(lifetime, created.Signal)
            return created
        end
        return channel
    end

    --------------------------------------------------------------------------------
    -- Channels
    --------------------------------------------------------------------------------

    function bridge:Publish(channel: string, value: any): ()
        assertAlive("Publish")
        local name = assertName(channel, "Publish", "channel")

        local entry = channelFor(name)
        entry.Value = value
        entry.HasValue = true
        entry.Signal:Fire(value)
    end

    function bridge:Subscribe(channel: string, handler: (value: any) -> ()): Types.Connection
        assertAlive("Subscribe")
        local name = assertName(channel, "Subscribe", "channel")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :Subscribe("{name}") expects a function, got {typeof(handler)}.`, 0)
        end

        local entry = channelFor(name)
        local connection = entry.Signal:Connect(handler)

        --[[
            The retained value is delivered on a new thread rather than inline. Subscribing
            usually happens while an element is being adopted, and a handler that yields --
            or throws -- must not stall adoption of the rest of the screen. The `Connected`
            re-check covers a subscriber that disconnects in the same frame it subscribed.
        ]]
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

    --------------------------------------------------------------------------------
    -- Commands
    --------------------------------------------------------------------------------

    function bridge:Dispatch(command: string, payload: any): ()
        assertAlive("Dispatch")
        local name = assertName(command, "Dispatch", "command")

        local registered = handlers[name]
        if registered == nil or #registered == 0 then
            return
        end

        -- Snapshot: a handler is allowed to add or drop another handler mid-dispatch.
        for _, handler in table.clone(registered) do
            --[[
                Handler isolation. A button wired in Studio can reach any handler, and one
                system throwing must not swallow the click for every other listener -- so
                each runs under `xpcall` and the traceback is reported where it is useful.

                The traceback lands in an upvalue rather than in `xpcall`'s second return,
                because a `CommandHandler` returns nothing and so there is no second return
                to put it in.
            ]]
            local failure: string? = nil
            local ok = xpcall(handler, function(err: any): ()
                failure = debug.traceback(tostring(err), 2)
            end, payload)

            if not ok then
                warn(`[Unrest.Bridge] handler for "{name}" errored:\n{tostring(failure)}`)
            end
        end
    end

    function bridge:Handle(command: string, handler: Types.CommandHandler): Types.Connection
        assertAlive("Handle")
        local name = assertName(command, "Handle", "command")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :Handle("{name}") expects a function, got {typeof(handler)}.`, 0)
        end

        local registered = handlers[name]
        if registered == nil then
            registered = {}
            handlers[name] = registered
        end
        table.insert(registered, handler)

        local connection = { Connected = true }
        local function disconnect(): ()
            if not connection.Connected then
                return
            end
            connection.Connected = false
            local list = handlers[name]
            if list == nil then
                return
            end
            local index = table.find(list, handler)
            if index ~= nil then
                table.remove(list, index)
            end
        end
        connection.Disconnect = disconnect

        return (connection :: any) :: Types.Connection
    end

    --------------------------------------------------------------------------------

    function bridge:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        table.clear(channels)
        table.clear(handlers)
        Scope.destroy(lifetime)
    end

    return (bridge :: any) :: Types.Bridge
end

return Bridge
