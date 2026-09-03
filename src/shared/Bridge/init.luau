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
local Slots = require(script.Parent.Util.Slots)
local Types = require(script.Parent.Types)

type Channel = {
    Value: any,
    HasValue: boolean,
    Signal: Types.Signal<any>,
}

--[[
    Variadic return so `xpcall` is typed as `(boolean, ...any)` rather than `(boolean)`. A
    `CommandHandler` is declared as returning nothing, which would otherwise hide the message
    handler's return from the checker; the value is there at runtime either way.
]]
type Dispatchable = (any) -> ...any

--- A live handler, or the hole a mid-dispatch drop left. See `Util/Slots` for the rule.
type CommandSlot = Slots.Slot<Types.CommandHandler>

--[[
    Every handler registered against one command name, plus the bookkeeping that lets
    `Dispatch` walk the list without copying it. `Depth` counts the dispatches of this command
    currently on the stack -- a handler is allowed to dispatch the command it is handling, so a
    boolean would be cleared by the inner call and let it compact the list the outer loop is
    still indexing into. `Vacated` records that somebody dropped a handler while a dispatch was
    running, so the list is squeezed once the outermost one unwinds.

    The dense-array rule itself lives in `Util/Slots`, which `Util/Signal` follows too. Only
    the counter is per-caller: a signal counts fires of itself, this counts dispatches of one
    command name.
]]
type Command = {
    List: { CommandSlot },
    Depth: number,
    Vacated: boolean,
}

--[[
    `xpcall`'s message handler, hoisted to module level so a dispatch does not mint one of
    these per handler per call. Where a function is *written* does not move it on the call
    stack, so level 2 still means here what it meant inside `Dispatch`: the frame that raised,
    which is the handler, and never the Bridge. `return debug.traceback(...)` is a tail call,
    so on a VM that elides this frame the trace simply starts one line lower -- at the handler
    itself rather than at the `error` it called. The same handler is named either way.
]]
local function traceback(err: any): string
    return debug.traceback(tostring(err), 2)
end

local Bridge = {}

function Bridge.new(context: Types.RuntimeContext): Types.Bridge
    if context ~= "Server" and context ~= "Client" then
        error(`[Unrest.Bridge] .new expects "Server" or "Client", got {tostring(context)}.`, 0)
    end

    local channels: { [string]: Channel } = {}
    local handlers: { [string]: Command } = {}
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
        if registered == nil then
            return
        end

        --[[
            No snapshot. A handler is still allowed to add or drop another handler
            mid-dispatch, and both cases stay correct without one: `last` is read before the
            first handler runs, so a handler added now is not reached until the next dispatch
            -- which is what copying the list did too -- and a handler dropped now has its slot
            vacated rather than removed, so every index this loop holds stays put. The list is
            compacted below, once the outermost dispatch of this command unwinds.

            The one thing the copy did that this does not: a handler dropped mid-dispatch and
            not yet reached used to run anyway, off the copy. It is skipped now, which is what
            `Handle`'s caller asked for when it disconnected.
        ]]
        local list = registered.List
        local last = #list
        if last == 0 then
            return
        end

        registered.Depth += 1
        for index = 1, last do
            local handler = list[index]
            if type(handler) == "function" then
                --[[
                    Handler isolation. A button wired in Studio can reach any handler, and one
                    system throwing must not swallow the click for every other listener -- so
                    each runs under `xpcall` and the traceback is reported where it is useful.

                    On failure `xpcall` returns false plus whatever the message handler
                    returned -- regardless of what the called function would have returned had
                    it succeeded -- so the traceback arrives as the second return, and no
                    per-handler closure is needed to carry it out in an upvalue.
                ]]
                local ok, err = xpcall(handler :: Dispatchable, traceback, payload)
                if not ok then
                    warn(`[Unrest.Bridge] handler for "{name}" errored:\n{tostring(err)}`)
                end
            end
        end
        registered.Depth -= 1

        if registered.Depth == 0 and registered.Vacated then
            registered.Vacated = false
            Slots.compact(list)
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
            registered = {
                List = {},
                Depth = 0,
                Vacated = false,
            }
            handlers[name] = registered
        end
        table.insert(registered.List, handler)

        local connection = { Connected = true }
        local function disconnect(): ()
            if not connection.Connected then
                return
            end
            connection.Connected = false
            local entry = handlers[name]
            if entry == nil then
                return
            end
            local index = table.find(entry.List, handler)
            if index == nil then
                return
            end
            if entry.Depth > 0 then
                -- A dispatch is walking this list; vacate the slot and let it compact on the
                -- way out, so the indices that dispatch is holding do not shift underneath it.
                entry.List[index] = false
                entry.Vacated = true
            else
                table.remove(entry.List, index)
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
