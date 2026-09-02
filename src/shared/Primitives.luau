--!strict
--[[
    Unrest / Primitives

    The handful of types every other type module needs. This module has ZERO requires and
    nothing else in the framework may create a cycle through it.
]]

export type RuntimeContext = "Server" | "Client"

--- A plain teardown function.
export type Cleanup = () -> ()

--- The framework's own connection object (returned by `Signal:Connect`).
export type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

export type Destroyable = { Destroy: (self: any) -> () }
export type Disconnectable = { Disconnect: (self: any) -> () }

--- Every value a `Maid` knows how to clean up.
export type MaidTask = Instance | RBXScriptConnection | thread | Cleanup | Destroyable | Disconnectable

--- Deterministic, ordered cleanup container. Tasks are cleaned in reverse insertion order.
export type Maid = {
    Add: (self: Maid, item: MaidTask, key: string?) -> MaidTask,
    Remove: (self: Maid, key: string) -> (),
    Clean: (self: Maid) -> (),
    Destroy: (self: Maid) -> (),
    IsDestroyed: (self: Maid) -> boolean,
}

--- Minimal, dependency-free signal.
export type Signal<T...> = {
    Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
    Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
    Wait: (self: Signal<T...>) -> T...,
    Fire: (self: Signal<T...>, T...) -> (),
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}

return table.freeze({})
