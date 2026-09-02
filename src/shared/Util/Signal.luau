--!strict
--[[
    Unrest / Bridge / Signal

    A dependency-free signal. Closure based rather than metatable based so that every field
    is typed under `--!strict` without `self :: any` escapes.

    A handler that throws does not stop the remaining handlers: the error is re-raised on a
    fresh thread so it still lands in the output with a stack trace.
]]

local Types = require(script.Parent.Parent.Types)

-- Variadic return so `pcall` is typed as (boolean, ...any) rather than (boolean).
type Handler = (...any) -> ...any

local Signal = {}

--- Creates a signal. `name` only shows up in error messages.
function Signal.new<T...>(name: string?): Types.Signal<T...>
    local label = name or "Signal"
    local handlers: { Handler } = {}
    local alive = true

    local signal = {}

    function signal:Fire(...: any): ()
        if not alive then
            return
        end
        -- Snapshot so a handler may disconnect itself (or others) mid-dispatch.
        local snapshot = table.clone(handlers)
        for _, handler in snapshot do
            local ok, err = pcall(handler, ...)
            if not ok then
                local message = `[Unrest.Signal] "{label}" handler errored: {tostring(err)}`
                task.spawn(function()
                    error(message, 0)
                end)
            end
        end
    end

    function signal:Connect(handler: Handler): Types.Connection
        if type(handler) ~= "function" then
            error(`[Unrest.Signal] "{label}":Connect expects a function, got {typeof(handler)}`, 0)
        end
        table.insert(handlers, handler)

        local connection = { Connected = true }

        -- Declared as a plain closure (not `function connection:Disconnect`) so it does not
        -- shadow the enclosing method's implicit `self`.
        local function disconnect(): ()
            if not connection.Connected then
                return
            end
            connection.Connected = false
            local index = table.find(handlers, handler)
            if index ~= nil then
                table.remove(handlers, index)
            end
        end

        connection.Disconnect = disconnect

        return (connection :: any) :: Types.Connection
    end

    function signal:Once(handler: Handler): Types.Connection
        local connection: Types.Connection
        connection = signal:Connect(function(...)
            connection:Disconnect()
            handler(...)
        end)
        return connection
    end

    function signal:Wait(): ...any
        local thread = coroutine.running()
        local connection: Types.Connection
        connection = signal:Connect(function(...)
            connection:Disconnect()
            task.spawn(thread, ...)
        end)
        return coroutine.yield()
    end

    function signal:DisconnectAll(): ()
        table.clear(handlers)
    end

    function signal:Destroy(): ()
        alive = false
        table.clear(handlers)
    end

    return (signal :: any) :: Types.Signal<T...>
end

return Signal
