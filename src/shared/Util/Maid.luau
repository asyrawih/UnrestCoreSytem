--!strict
--[[
    Unrest / Bridge / Maid

    Ordered cleanup. Anonymous tasks are cleaned in reverse insertion order, which is what
    you want when later tasks were built on top of earlier ones. Keyed tasks replace (and
    clean) whatever was previously stored under the same key -- handy for "the connection
    for the current character" style state.

    Lives next to Signal because both are Bridge-owned primitives, but any layer may use it.
]]

local Types = require(script.Parent.Parent.Types)

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

function Maid.new(): Types.Maid
    local ordered: { any } = {}
    local keyed: { [string]: any } = {}
    local destroyed = false

    local maid = {}

    function maid:Add(item: Types.MaidTask, key: string?): Types.MaidTask
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

    return (maid :: any) :: Types.Maid
end

return Maid
