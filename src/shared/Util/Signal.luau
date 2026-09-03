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
    Unrest / Bridge / Signal

    A dependency-free signal. Every method lives on one metatable built once at module load,
    so `Signal.new` allocates the instance table and nothing else -- the handler array is not
    created until somebody actually connects. That shape is chosen for a reason: `Elements`
    mints a `Released` signal for every adopted element, and most of a screen is never
    subscribed to, so a three-hundred-element screen used to pay six closures and two tables
    for three hundred signals that never fired.

    The cost of the shared metatable is that the private state type and the public
    `Types.Signal<T...>` are different types, so `new` casts through `any` on its way out --
    the same `(x :: any) :: T` the rest of the framework uses at its boundaries.

    FIRING DOES NOT COPY THE HANDLER LIST. A dispatch walks the live array by index between
    bounds captured before the first handler runs, so a handler connected mid-dispatch is not
    called until the next fire -- which is what the snapshot this replaces did too. A handler
    disconnected mid-dispatch has its slot replaced with `false` rather than removed, because
    removing it would shift every later handler out from under the loop's indices; the array
    is compacted once the last fire on the stack unwinds.

    `depth` is a counter rather than a boolean because a handler is allowed to fire the signal
    it is running under. A boolean would be cleared by the inner fire and let it compact the
    array the outer loop is still indexing into, which would skip or double-call handlers.

    The one semantic this buys that the snapshot did not have: a disconnect made during a
    dispatch takes effect within that dispatch, so a handler that has not been reached yet
    does not run. That is the ordinary signal semantic, and the one `Once` already depended on
    for itself.

    A handler that throws does not stop the remaining handlers: the error is re-raised on a
    fresh thread so it still lands in the output with a stack trace.
]]

local Slots = require(script.Parent.Slots)
local Types = require(script.Parent.Parent.Types)

-- Variadic return so `pcall` is typed as (boolean, ...any) rather than (boolean).
type Handler = (...any) -> ...any

--- A live handler, or the hole a mid-dispatch disconnect left. See `Util/Slots` for the rule.
type Slot = Slots.Slot<Handler>

type State = {
    label: string,
    alive: boolean,
    depth: number,
    vacated: boolean,
    slots: { Slot }?,
}

--- The handler array, created on first `Connect`. A signal nobody listens to never pays for
--- one, which is most of them.
local function slotsOf(self: State): { Slot }
    local existing = self.slots
    if existing ~= nil then
        return existing
    end
    local created: { Slot } = {}
    self.slots = created
    return created
end

--- Drops every handler. During a fire the slots are vacated in place rather than cleared,
--- because the loop that is running holds indices into this exact array.
local function drop(self: State): ()
    local slots = self.slots
    if slots == nil then
        return
    end
    if self.depth > 0 then
        Slots.vacateAll(slots)
        self.vacated = true
    else
        table.clear(slots)
    end
end

local methods = {}
local metatable = { __index = methods }

function methods.Fire(self: State, ...: any): ()
    if not self.alive then
        return
    end
    local slots = self.slots
    if slots == nil then
        return
    end

    -- Bounds read before the first handler runs, so a handler that connects another one does
    -- not extend the dispatch it is already inside.
    local last = #slots
    self.depth += 1
    for index = 1, last do
        local handler = slots[index]
        -- Narrowed with `type` rather than truthiness because that is the test Luau refines a
        -- `Handler | false` union on; a bare `if handler then` leaves the boolean half in.
        if type(handler) == "function" then
            local ok, err = pcall(handler, ...)
            if not ok then
                local message = `[Unrest.Signal] "{self.label}" handler errored: {tostring(err)}`
                task.spawn(function()
                    error(message, 0)
                end)
            end
        end
    end
    self.depth -= 1

    if self.depth == 0 and self.vacated then
        self.vacated = false
        Slots.compact(slots)
    end
end

function methods.Connect(self: State, handler: Handler): Types.Connection
    if type(handler) ~= "function" then
        error(`[Unrest.Signal] "{self.label}":Connect expects a function, got {typeof(handler)}`, 0)
    end
    table.insert(slotsOf(self), handler)

    local connection = { Connected = true }

    --[[
        A closure rather than a method on the shared metatable, because it has to close over
        three things at once -- the signal, the handler and the connection it belongs to --
        and because it stays callable whether a caller writes `connection:Disconnect()` or
        passes the field around as a plain function.
    ]]
    local function disconnect(): ()
        if not connection.Connected then
            return
        end
        connection.Connected = false

        local slots = self.slots
        if slots == nil then
            return
        end
        local index = table.find(slots, handler)
        if index == nil then
            return
        end
        if self.depth > 0 then
            -- A fire is walking this array; vacate the slot and let it compact on the way out.
            slots[index] = false
            self.vacated = true
        else
            table.remove(slots, index)
        end
    end

    connection.Disconnect = disconnect

    return (connection :: any) :: Types.Connection
end

function methods.Once(self: State, handler: Handler): Types.Connection
    local connection: Types.Connection
    connection = methods.Connect(self, function(...)
        connection:Disconnect()
        handler(...)
    end)
    return connection
end

function methods.Wait(self: State): ...any
    local thread = coroutine.running()
    local connection: Types.Connection
    connection = methods.Connect(self, function(...)
        connection:Disconnect()
        task.spawn(thread, ...)
    end)
    return coroutine.yield()
end

function methods.DisconnectAll(self: State): ()
    drop(self)
end

function methods.Destroy(self: State): ()
    self.alive = false
    drop(self)
end

local Signal = {}

--- Creates a signal. `name` only shows up in error messages.
function Signal.new<T...>(name: string?): Types.Signal<T...>
    local signal: State = {
        label = name or "Signal",
        alive = true,
        depth = 0,
        vacated = false,
        slots = nil,
    }
    return (setmetatable(signal, metatable) :: any) :: Types.Signal<T...>
end

return Signal
