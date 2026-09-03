--!strict
--[[
    Unrest / Util / Scope

    The one place in the framework that names where Scythe lives.

    Scythe is a cleanup library with no objects. A scope is an integer handle into
    module-level Structure-of-Arrays storage, the disposal method is resolved once at `add`
    time and stored as a byte, and the teardown loop branches on that byte instead of asking
    `typeof`. Compared with the closure-per-scope container it replaces, opening a scope
    allocates nothing on the Lua heap that survives the call.

    WHY THIS FILE EXISTS AT ALL, rather than every module requiring `Packages.Scythe`
    directly. Scythe keeps its storage in module upvalues, so two copies of the module are
    two disjoint universes: a handle minted by one is, to the other, either an unallocated
    slot or -- far worse -- a live slot belonging to something else. Roblox gives you a
    second copy the moment two require paths reach two different Instances. Writing the path
    exactly once means there is only ever one Scythe, and the framework and the game around
    it can hand scopes to each other.

    That is also why `Unrest.Scope` re-exports this on the singleton. Game code that wants to
    park a connection on a scope the framework handed it should reach for `unrest.Scope`
    rather than requiring Scythe again and hoping the paths agree.

    This is the framework's only third-party dependency, and it is a deliberate exception:
    the thing it replaces was the framework's single largest source of allocation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scythe = require(ReplicatedStorage.Packages.Scythe)

return Scythe
