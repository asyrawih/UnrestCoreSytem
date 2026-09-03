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
    Bench / Cleanup

    The headline benchmark: the framework's OLD closure-based Maid against the NEW Scythe
    scopes, on the three cleanup shapes the framework actually has.

    This is a `.bench` module, so its Instance name ends in `.bench` and the Scriptbench
    plugin (or boatbomber's Benchmarker, which shares the format) offers it in its file
    list. Build the place with `bench.project.json` and it lands at
    `ReplicatedStorage.Bench.Cleanup.bench`:

        rojo build bench.project.json --output bench.rbxl

    then open it in Studio and pick this file in the Scriptbench plugin. Run
    `TableFill.bench` first -- it has a known answer, so a number out of it proves the
    plugin works before anything here is believed.

    WHAT IS BEING COMPARED. Every pair below does identical work under the two
    implementations -- same number of disposables, same order, same teardown call -- so the
    only difference the clock can see is the container. The three shapes are the ones the
    framework spends its life in:

        add 8, destroy              one adopted element: an adapter binds a handful of
                                    events and attribute watches, then the element is
                                    released in one line;
        add 1, destroy              one binding: the smallest unit the framework opens a
                                    container for, and the one it opens most often;
        add 8, clean, add 8, destroy    a rewire: an element whose attributes changed, so
                                    everything it owned is released and bound again
                                    against the same container.

    WHAT IT DELIBERATELY DOES NOT MEASURE.

    The disposables are plain `function() end` closures. Nothing here touches the Instance
    API, connects a signal or spawns a thread, because those are Roblox's costs and they
    are identical on both sides -- letting them in would bury the difference under work
    neither container is responsible for. What is left is the container: opening it,
    recording into it, and draining it.

    It is also wall clock ONLY. Scythe's claim is about the Lua heap, and no benchmark in
    this format can see the heap at all -- Benchmarker and Scriptbench have no memory hook.
    `studio/HeapProfile.luau` is the other half of this comparison, and the argument is not
    settled without it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[
    HOW A BENCH FILE IS ALLOWED TO REQUIRE THINGS.

    Scriptbench requires a `.bench` module through a CLONE of it, and that clone has no
    parent. So `script` is useless in here: `script.Parent` is nil, and a relative require
    dies with "attempt to index nil with ..." before the picker can even read the file's
    name. Everything a bench file needs must be reached from a service instead.

    The folder is searched for rather than named, too. Its name is a mount decision that
    lives in `bench.project.json`, and renaming it there -- or dragging the folder around in
    Studio -- must not turn this into a nil index with no explanation attached.
]]
local function baseline(name: string): ModuleScript
    for _, child in ReplicatedStorage:GetChildren() do
        local folder = child:FindFirstChild("Baseline")
        if folder ~= nil then
            local module = folder:FindFirstChild(name)
            if module ~= nil and module:IsA("ModuleScript") then
                return module
            end
        end
    end

    error(
        `[Bench] cannot find Baseline.{name} anywhere under ReplicatedStorage. `
            .. `Build the place with bench.project.json rather than default.project.json -- `
            .. `that is the project file that mounts bench/ into the DataModel.`,
        0
    )
end

--[[
    `require` is cast because luau-lsp resolves require paths statically and cannot see
    through the lookup above -- without the cast it reports "unsupported path". The shape is
    then pinned by hand so the benchmark bodies below are still type-checked: this is a
    deleted module's historical API, so pinning it here cannot drift out of step with
    anything that is still alive.
]]
type BaselineMaid = {
    Add: (self: BaselineMaid, item: any, key: string?) -> any,
    Clean: (self: BaselineMaid) -> (),
    Destroy: (self: BaselineMaid) -> (),
}

local Maid = (require :: any)(baseline("Maid")) :: { new: () -> BaselineMaid }
--[[
    Scythe is required through the framework's re-export, never through
    `ReplicatedStorage.Packages.Scythe` directly.

    Scythe keeps its scope storage in module upvalues, so two copies of the module are two
    disjoint universes: a handle minted by one is, to the other, either an unallocated slot
    or -- far worse -- a live slot belonging to something else. Roblox hands you a second
    copy the moment two require paths reach two different Instances. `Unrest.Util.Scope` is
    the one file in the repository allowed to name Scythe's path, and a benchmark that went
    around it would be timing a Scythe the framework has never met.
]]
local Scope = require(ReplicatedStorage.Unrest.Util.Scope)

--[[
    Scriptbench passes a profiler as the first argument to every benchmark function. It is
    typed here so the file can stay `--!strict`, and it is deliberately unused: at this
    scale a `Begin`/`End` pair costs more than the work it would be bracketing, so labelling
    these regions would produce a flame chart of the profiler rather than of the container.
]]
type Profiler = {
    Begin: (label: string) -> (),
    End: () -> (),
}

--- The disposables handed to one benchmark call: 8 for the first fill, 8 more for a rewire.
type Disposables = { () -> () }

local ITEMS = 8

return {
    --[[
        Runs OUTSIDE the timer, once per call, and its return is passed to the benchmark
        function after the profiler.

        The closures are built HERE, not inside the functions below, and that is the single
        most important line in this file. A closure is an allocation; building sixteen of
        them inside the timed region would make every one of the six measurements below
        mostly a measurement of closure creation, which is identical on both sides and would
        therefore compress the difference between the containers towards nothing. Pre-built
        out here, the timed region contains the container and nothing else.

        Exactly ONE value is returned, on purpose. Scriptbench forwards only the first
        return of `ParameterGenerator` -- a bug in its `benchmark.ts` -- so a generator that
        returned a tuple would silently lose everything after the first element.
    ]]
    ParameterGenerator = function(): Disposables
        local disposables: Disposables = table.create(ITEMS * 2)
        for index = 1, ITEMS * 2 do
            disposables[index] = function() end
        end
        return disposables
    end,

    Functions = {
        ["Maid: add 8, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local maid = Maid.new()
            for index = 1, ITEMS do
                maid:Add(disposables[index])
            end
            maid:Destroy()
        end,

        ["Scythe: add 8, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local scope = Scope.scope()
            for index = 1, ITEMS do
                Scope.add(scope, disposables[index])
            end
            Scope.destroy(scope)
        end,

        ["Maid: add 1, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local maid = Maid.new()
            maid:Add(disposables[1])
            maid:Destroy()
        end,

        ["Scythe: add 1, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local scope = Scope.scope()
            Scope.add(scope, disposables[1])
            Scope.destroy(scope)
        end,

        ["Maid: add 8, clean, add 8, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local maid = Maid.new()
            for index = 1, ITEMS do
                maid:Add(disposables[index])
            end
            maid:Clean()
            for index = ITEMS + 1, ITEMS * 2 do
                maid:Add(disposables[index])
            end
            maid:Destroy()
        end,

        ["Scythe: add 8, clean, add 8, destroy"] = function(_profiler: Profiler, disposables: Disposables)
            local scope = Scope.scope()
            for index = 1, ITEMS do
                Scope.add(scope, disposables[index])
            end
            Scope.clean(scope)
            for index = ITEMS + 1, ITEMS * 2 do
                Scope.add(scope, disposables[index])
            end
            Scope.destroy(scope)
        end,
    },
}
