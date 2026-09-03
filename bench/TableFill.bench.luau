--!strict
--[[
    Bench / TableFill

    The smoke test. Run this FIRST, before the benchmarks that mean something: if numbers
    come out of this one, the plugin is installed and the `.bench` discovery works, and any
    problem with the others is the others' problem.

    It also demonstrates the format itself, so keep it around as the thing to copy from. It
    compares filling a preallocated table against filling an empty one -- a comparison with
    a known answer, which is the whole point of a smoke test. `table.create` should win, and
    the "Create" label should be the part that differs while "Fill" stays about level.

    ON THE TWO SPELLINGS. Scriptbench accepts `Name` and `Parameter`, and its profiler
    answers to `profilebegin` / `profileend` as well as `Begin` / `End`. Those are
    Scriptbench's own extensions. The portable spellings -- the ones boatbomber's
    Benchmarker also understands -- are `ParameterGenerator` and `Profiler.Begin` /
    `Profiler.End`, and that is what the other bench files in this folder use. This file
    uses the Scriptbench spellings deliberately, so that it proves BOTH halves work.

    Build with `bench.project.json` and it lands at `ReplicatedStorage.Bench.TableFill.bench`.
    See `docs/BENCHMARKING.md`.
]]

--- Not influenced by the benchmark; it must stay constant or the two rows stop comparing.
local SIZE = 2500

--[[
    The profiler handed to every benchmark function as its first argument. Typed so the file
    can stay `--!strict`; a `Begin`/`End` pair costs well under a microsecond, so bracketing
    regions this size is honest.
]]
type Lib = {
    profilebegin: (label: string) -> (),
    profileend: () -> (),
    Begin: (label: string) -> (),
    End: () -> (),
}

return {
    Name = "Table Fill",

    --[[
        One argument, generated fresh per call and OUTSIDE the timer.

        Exactly one value is returned, on purpose: Scriptbench forwards only the first
        return of the generator, so a tuple would silently lose everything after the first.
    ]]
    Parameter = function(): number
        return math.random(1, 100)
    end,

    -- Set-up and tear-down, none of it timed. Empty here; there is nothing to prepare.
    BeforeAll = function(): () end,
    AfterAll = function(): () end,
    BeforeEach = function(): () end,
    AfterEach = function(): () end,

    Functions = {
        ["table.create"] = function(lib: Lib, value: number): ()
            lib.profilebegin("Create")
            local tb = table.create(SIZE)
            lib.profileend()

            lib.profilebegin("Fill")
            for index = 1, SIZE do
                tb[index] = value
            end
            lib.profileend()
        end,

        ["Empty Table"] = function(lib: Lib, value: number): ()
            lib.profilebegin("Create")
            local tb = {}
            lib.profileend()

            lib.profilebegin("Fill")
            for index = 1, SIZE do
                tb[index] = value
            end
            lib.profileend()
        end,
    },
}
