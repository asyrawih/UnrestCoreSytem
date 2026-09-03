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
    Bench / Baseline / Maid

    The framework's OLD cleanup container, kept alive here so the benchmark next door
    compares against code that actually shipped rather than against a re-creation of it
    from memory. A re-creation would be the benchmark author's idea of the old Maid, and
    the number it produced would be an argument about that idea instead of a measurement.

    Provenance: `src/shared/Util/Maid.luau` as of commit 80a6e97, the parent of be63033
    ("Replace the Maid with Scythe scopes throughout the framework"), recovered with

        git show 80a6e97:src/shared/Util/Maid.luau

    ONE edit was made to the recovered file, and it is the whole diff: the original opened
    with `local Types = require(script.Parent.Parent.Types)` and annotated itself with
    `Types.Maid` / `Types.MaidTask`. Those exports went with the Maid, and the require path
    would not resolve from `ReplicatedStorage.Bench.Baseline` anyway, so the two type
    aliases are restated below exactly as `src/shared/Primitives.luau` declared them at
    80a6e97. No line of the implementation itself was touched -- the allocation shape being
    measured is byte-for-byte the one the framework used to pay for.

    This file is deliberately NOT under `src/`. It is dead code that exists to lose a race;
    shipping it in the normal build would put a second cleanup vocabulary back in the
    framework, which is exactly what be63033 removed.

    ---- the original header follows ----

    Unrest / Bridge / Maid

    Ordered cleanup. Anonymous tasks are cleaned in reverse insertion order, which is what
    you want when later tasks were built on top of earlier ones. Keyed tasks replace (and
    clean) whatever was previously stored under the same key -- handy for "the connection
    for the current character" style state.

    Lives next to Signal because both are Bridge-owned primitives, but any layer may use it.
]]

--- Restated from `src/shared/Primitives.luau` at 80a6e97. See the note above.
export type Cleanup = () -> ()
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

local Maid = {}

local function cleanup(item: any): ()
    local kind = typeof(item)
    if kind == "function" then
        item()
    elseif kind == "RBXScriptConnection" then
        item:Disconnect()
    elseif kind == "Instance" then
        item:Destroy()
    elseif kind == "thread" then
        pcall(task.cancel, item)
    elseif kind == "table" then
        if type(item.Disconnect) == "function" then
            item:Disconnect()
        elseif type(item.Destroy) == "function" then
            item:Destroy()
        else
            error("[Unrest.Maid] table tasks must expose :Destroy() or :Disconnect()", 0)
        end
    else
        error(`[Unrest.Maid] cannot clean up a value of type {kind}`, 0)
    end
end

function Maid.new(): Maid
    local ordered: { any } = {}
    local keyed: { [string]: any } = {}
    local destroyed = false

    local maid = {}

    function maid:Add(item: MaidTask, key: string?): MaidTask
        if destroyed then
            -- The maid already ran; anything handed to it now is dead on arrival.
            cleanup(item :: any)
            return item
        end

        if key ~= nil then
            local previous = keyed[key]
            keyed[key] = item
            if previous ~= nil then
                cleanup(previous)
            end
        else
            table.insert(ordered, item)
        end

        return item
    end

    function maid:Remove(key: string): ()
        local previous = keyed[key]
        if previous == nil then
            return
        end
        keyed[key] = nil
        cleanup(previous)
    end

    function maid:Clean(): ()
        local pending = ordered
        ordered = {}
        for index = #pending, 1, -1 do
            cleanup(pending[index])
        end

        local pendingKeys = keyed
        keyed = {}
        for _, item in pendingKeys do
            cleanup(item)
        end
    end

    function maid:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        maid:Clean()
    end

    function maid:IsDestroyed(): boolean
        return destroyed
    end

    return (maid :: any) :: Maid
end

return Maid
