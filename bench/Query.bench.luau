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
    Bench / Query

    What the framework pays PER ELEMENT, on the read-only half of `Selector`.

    Every one of these functions runs once per candidate per sweep, and again on every
    rename, tag change and attribute change that a live query watches. A screen of forty
    buttons multiplies each number below by forty before anything is drawn, which is why
    they are worth a graph at all.

    RE-RUN THIS AFTER THE SELECTOR WALK-HOISTING CHANGE LANDS. These are the numbers that
    change: `groupOf` and `attributeOf` currently climb the ancestor chain more than once
    for a single answer -- `presetFor` walks it, and then the inheritable layer walks it
    again -- and hoisting the walk is supposed to show up here as a drop in exactly those
    two rows, with `roleOf` (which never walks) unmoved as the control.

    WHAT IT DELIBERATELY DOES NOT MEASURE.

    `Unrest:Query` itself is NOT benchmarked, and must not be. A query registers live
    CollectionService connections and ancestor watches that outlive the call; running one a
    few thousand times inside a timing loop would leave a few thousand live subscriptions
    behind, poisoning every later run in the same Studio session and eventually the session
    itself. `Selector` is the pure half -- no state, no connections -- so it is the half a
    benchmark can safely hammer.

    Nor does it measure adoption, adapter resolution or binding. Those touch systems and
    Instances; this file is the predicate only.

    Wall clock ONLY, like every module in this format. See `studio/HeapProfile.luau` for
    heap.

    A NOTE ON THE FIXTURE. `BeforeAll` builds a throwaway tree under `ReplicatedStorage` and
    `AfterAll` destroys it. Benches run in Studio's EDIT-mode DataModel against the real
    place, so those instances are briefly real instances in your file -- do not save the
    place while a run is in flight, and if a run is interrupted, delete
    `ReplicatedStorage.UnrestBenchFixture` by hand. Nothing here yields, because a bench
    that yields is a bench with a garbage number in it.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Selector = require(ReplicatedStorage.Unrest.Adapters.Selector)
local Types = require(ReplicatedStorage.Unrest.Types)

type Profiler = {
    Begin: (label: string) -> (),
    End: () -> (),
}

local FIXTURE_NAME = "UnrestBenchFixture"
local GROUP = "BenchGroup"
local LEAF_ROLE = "BenchLeaf"

--[[
    Shape of the tree, chosen to look like a real screen rather than to flatter anybody.

    `DEPTH` is what the ancestor walk has to climb before it reaches the `ScreenGui` and
    stops: a leaf sits four containers below the panel root, which is an ordinary amount of
    nesting for a hand-built menu. `PANELS * LEAVES_PER_PANEL` leaves exist so the generator
    can hand out a different one each call and the measurement is not a measurement of one
    lucky instance's property cache.
]]
local PANELS = 8
local DEPTH = 4
local LEAVES_PER_PANEL = 8

--[[
    The group lives on the `ScreenGui`, never on the leaves. That is the whole point: a
    group is inherited, so `groupOf` on a leaf has to walk, and the walk is the cost being
    measured. Writing the group on the leaves would turn the expensive row into the cheap
    one and the benchmark would report a lie.
]]
local fixture: Folder? = nil
local leaves: { Instance } = {}

--[[
    Compiled at load, not per call. `Selector.parse` validates the descriptor through the
    Resolver, and that validation is a setup cost a caller pays once per query -- charging
    it to every `matches` call would measure the Resolver instead.

    BOTH CARRY THE TAG, and not by preference: a descriptor with no `Tag` must supply an
    `Ancestor`, or the Resolver refuses it. A tagless, rootless query would have to scan the
    whole DataModel, so the framework will not let one exist. There is no `Ancestor` to give
    at load time either -- the fixture is not built until `BeforeAll`.

    That turns out to be the better pair anyway. Both rows now pay the same `isManaged`
    climb, so the only thing separating them is how the second half of the predicate is
    answered: a role is read off the instance, a group is resolved up the chain. One
    variable, which is what a comparison is for.
]]
local ROLE_FILTER: Types.CompiledSelector = Selector.parse({ Tag = Constants.Tag, Role = LEAF_ROLE })
local GROUP_FILTER: Types.CompiledSelector = Selector.parse({ Tag = Constants.Tag, Group = GROUP })

--[[
    Idempotent, so it is safe to call from `BeforeAll` and safe to call again as a guard.
    The guard matters because the order in which a host calls `BeforeAll` and the first
    `ParameterGenerator` is the host's business, not this file's, and a generator that
    indexed an empty `leaves` would fail the whole run with a nil index rather than with
    something a reader could act on.
]]
local function ensureFixture(): ()
    --[[
        `fixture.Parent ~= nil` as well as `fixture ~= nil`. A destroyed instance is still a
        perfectly truthy reference, so somebody clearing `UnrestBenchFixture` out of
        Explorer between runs would leave this holding a dead tree -- and dead is not an
        error here, it is worse: `isManaged` asks `IsDescendantOf(game)` first, so every
        `matches` row would quietly measure a fast rejection and report numbers that look
        like a win.
    ]]
    if fixture ~= nil and fixture.Parent ~= nil then
        return
    end

    -- An interrupted earlier run can leave one behind. Take it out rather than nest inside it.
    local stale = ReplicatedStorage:FindFirstChild(FIXTURE_NAME)
    if stale ~= nil then
        stale:Destroy()
    end

    table.clear(leaves)

    local root = Instance.new("Folder")
    root.Name = FIXTURE_NAME

    local screen = Instance.new("ScreenGui")
    screen.Name = "BenchScreen"
    screen:SetAttribute(Constants.Attributes.Group, GROUP)
    screen.Parent = root
    CollectionService:AddTag(screen, Constants.Tag)

    for panel = 1, PANELS do
        local parent: Instance = screen

        for level = 1, DEPTH do
            local container = Instance.new("Frame")
            container.Name = `Panel{panel}_Level{level}`
            container.Parent = parent
            parent = container
        end

        for leaf = 1, LEAVES_PER_PANEL do
            local frame = Instance.new("Frame")
            frame.Name = `Panel{panel}_Leaf{leaf}`
            frame:SetAttribute(Constants.Attributes.Role, LEAF_ROLE)
            frame.Parent = parent
            table.insert(leaves, frame)
        end
    end

    --[[
        Parented last. `Selector.isManaged` asks `IsDescendantOf(game)` before it reads the
        tag -- managed means tagged AND in the DataModel -- so nothing in this tree answers
        yes to anything until this line runs.
    ]]
    root.Parent = ReplicatedStorage
    fixture = root
end

return {
    BeforeAll = function()
        ensureFixture()
    end,

    AfterAll = function()
        local root = fixture
        fixture = nil
        table.clear(leaves)
        if root ~= nil then
            root:Destroy()
        end
    end,

    --[[
        Returns exactly ONE value -- a leaf, chosen at random so consecutive calls do not
        hammer the same instance. Scriptbench forwards only the first return of a generator
        (a bug in its `benchmark.ts`), so a tuple here would silently lose everything after
        the leaf.
    ]]
    ParameterGenerator = function(): Instance
        ensureFixture()
        return leaves[math.random(#leaves)]
    end,

    Functions = {
        --- The floor: one `GetAttribute`, no walk. The control row for every change below.
        ["roleOf"] = function(_profiler: Profiler, leaf: Instance)
            Selector.roleOf(leaf)
        end,

        --- The walk on its own, with no attribute reads on top of it.
        ["ancestorChain"] = function(_profiler: Profiler, leaf: Instance)
            Selector.ancestorChain(leaf)
        end,

        --[[
            A non-inheritable name that nothing sets. The interesting part is that this
            still pays for a chain walk: `attributeOf` consults the preset layer before it
            gives up, and resolving the preset is itself a walk.
        ]]
        ["attributeOf (UnrestCommand, absent)"] = function(_profiler: Profiler, leaf: Instance)
            Selector.attributeOf(leaf, Constants.Attributes.Command)
        end,

        --- The full ladder, and a hit at the top of it: own miss, preset miss, inherited hit.
        ["groupOf (inherited from the ScreenGui)"] = function(_profiler: Profiler, leaf: Instance)
            Selector.groupOf(leaf)
        end,

        --[[
            The tag climb plus a role read. `roleOf` needs no walk of its own, so whatever
            this costs above the `roleOf` row is what `isManaged` costs.
        ]]
        ["matches (Tag + Role)"] = function(_profiler: Profiler, leaf: Instance)
            Selector.matches(leaf, ROLE_FILTER)
        end,

        --[[
            The expensive predicate, and the realistic one. Same tag climb as the row above,
            and then the group is resolved, which climbs again -- so the gap between these
            two rows is the cost of resolving an inherited attribute, isolated. This is the
            row a live query re-runs on every watched edit.
        ]]
        ["matches (Tag + Group)"] = function(_profiler: Profiler, leaf: Instance)
            Selector.matches(leaf, GROUP_FILTER)
        end,
    },
}
