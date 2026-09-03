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
    Unrest / Util / Scope

    The one place in the framework that knows where Scythe is.

    Scythe is a cleanup library with no objects. A scope is an integer handle into
    module-level Structure-of-Arrays storage, the disposal method is resolved once at `add`
    time and stored as a byte, and the teardown loop branches on that byte instead of asking
    `typeof`. Compared with the closure-per-scope container it replaces, opening a scope
    allocates nothing on the Lua heap that survives the call.

    WHY THIS FILE EXISTS AT ALL, rather than every module requiring Scythe directly. Scythe
    keeps its storage in module upvalues, so two copies of the module are two disjoint
    universes: a handle minted by one is, to the other, either an unallocated slot or -- far
    worse -- a live slot belonging to something else. Roblox gives you a second copy the
    moment two require paths reach two different Instances. Deciding it once, here, means
    there is only ever one Scythe, and the framework and the game around it can hand scopes
    to each other. That is also why `Unrest.Scope` re-exports this on the singleton: game
    code reaching for cleanup should come through here rather than require Scythe again and
    hope the paths agree.

    WHY IT SEARCHES RATHER THAN NAMES A PATH. The framework ships three ways, and Scythe
    lands somewhere different in each:

      * installed from Wally      `Packages/_Index/<scope>_unrest-core-system@<ver>/Scythe`,
                                  a sibling of the package folder;
      * synced from source (Rojo) `ReplicatedStorage.Packages.Scythe`, from `wally install`;
      * inserted as a model       `Unrest.Scythe`, vendored into the model by
                                  `model.project.json` because a Creator Store insert has no
                                  package manager behind it and no `Packages` folder at all.

    A hard-coded path would be right for exactly one of those and would fail at require time
    for the other two -- and Roblox caches a module's load failure for the whole session, so
    the failure would outlive the fix. Walking up from here finds the first two; the third
    is the fallback. Whichever answers first is THE copy, which is the property that matters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Primitives = require(script.Parent.Parent.Primitives)

--[[
    Scythe's surface, written out rather than borrowed with `typeof`.

    Borrowing it would mean a static `require` of some fixed path purely for the checker,
    which is the exact coupling this file exists to remove -- and in a consumer's place that
    path may not exist, so our shipped code would fail *their* analyze run. A foreign
    library's surface pinned deliberately is the lesser evil; it is small, it is stable, and
    a drift shows up as a type error rather than as silence.
]]
export type Library = {
    --- Opens a scope. The handle packs a slot index and a generation counter; never do arithmetic on it.
    scope: () -> Primitives.Scope,
    --- Tracks a value and hands it straight back, so it composes inside an expression.
    add: <T>(scope: Primitives.Scope, value: T) -> T,
    --- Tracks several at once, atomically.
    addBulk: (scope: Primitives.Scope, ...any) -> (),
    --- Drops one tracked value without disposing the rest. True if it was found.
    remove: (scope: Primitives.Scope, value: any) -> boolean,
    --- Disposes everything, LIFO. The scope stays usable.
    clean: (scope: Primitives.Scope) -> (),
    --- Disposes everything and recycles the handle. Using the handle afterwards raises.
    destroy: (scope: Primitives.Scope) -> (),
    --- Live item count. One buffer read.
    count: (scope: Primitives.Scope) -> number,
    --- Non-throwing liveness check; false for destroyed, stale or malformed handles.
    isAlive: (scope: any) -> boolean,
}

local function locate(): ModuleScript
    --[[
        Upwards from here first. That covers the vendored copy sitting beside the framework
        in a Creator Store model, and Wally's link file sitting beside the package folder,
        without this file having to know which of the two it is looking at.
    ]]
    local current: Instance? = script.Parent
    while current ~= nil and current ~= game do
        local found = current:FindFirstChild("Scythe")
        if found ~= nil and found:IsA("ModuleScript") then
            return found
        end
        current = current.Parent
    end

    -- Then the `Packages` folder a source checkout syncs alongside the framework.
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if packages ~= nil then
        local module = packages:FindFirstChild("Scythe")
        if module ~= nil and module:IsA("ModuleScript") then
            return module
        end
    end

    error(
        "[Unrest.Scope] cannot find Scythe. Unrest needs it for cleanup and looks in three "
            .. "places: beside itself (a vendored copy, as in the Creator Store model), beside "
            .. "its own package folder (a Wally install), and at ReplicatedStorage.Packages.Scythe "
            .. "(a source checkout -- run `wally install`). None of the three answered.",
        0
    )
end

--[[
    `require` is cast because luau-lsp resolves require paths statically and cannot follow the
    search above; the result is then named by the surface declared at the top of this file, so
    everything downstream is still type-checked.
]]
local Scythe = (require :: any)(locate()) :: Library

return Scythe
