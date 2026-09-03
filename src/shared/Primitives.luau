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

--[[
    A cleanup scope: an opaque integer handle into Scythe's storage.

    It is a plain number so that holding one costs nothing -- a map of scopes is a map of
    numbers, not a map of tables. Never do arithmetic on it and never invent one: the handle
    packs a slot index and a generation counter, and a fabricated value either misses or,
    worse, addresses somebody else's scope.

    Declared here rather than imported so this module keeps its no-requires rule.
]]
export type Scope = number

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
