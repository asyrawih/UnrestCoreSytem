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
    Unrest Plugin / Framework

    Where the framework is, and nothing else. Every rule the plugin draws is read out of the
    place that is open -- `Constants`, `Selector`, `Presets`, `Adapters`, `Widgets/Schemas`,
    `Tooling/Lint`, `Tooling/Vocab` -- so the panel and the runtime cannot disagree about what
    a tag or an attribute means. THE PLUGIN CARRIES NO COPY OF A RULE. There is no attribute
    list here, no class table, no cascade; there is a `FindFirstChild` and a `require`.

    THE REQUIRE BOUNDARY. Only modules that are pure at require time may be loaded: they must
    touch no service that needs a running client and must assemble no singleton. `Widgets/init`
    and `Elements/init` hold `Players` and `UserInputService` at file scope and `Unrest/init`
    builds the singleton, so requiring any of the three from edit mode is an error waiting for
    a place that has not started. The list below is the whole of what this plugin loads, and it
    is the same list `src/shared/Tooling/` is allowed to load.

    UNTYPED ON PURPOSE. `plugin/` is its own Rojo project and its sourcemap knows nothing of
    `src/shared`, so `require(unrest.Constants)` is a dynamic require luau-lsp cannot resolve
    and every module below is `any`. Restating their signatures here would be a second copy of
    the framework's types, drifting the moment the framework moved -- exactly what this module
    exists to avoid. The types are checked where they are written.

    OLD FRAMEWORKS DEGRADE, THEY DO NOT FAIL. `Schemas`, `Lint` and `Vocab` are optional: a
    place on an older release simply has nil there, and the panels that need them say so and
    draw nothing else. Only `Constants`, `Selector`, `Presets` and `Adapters` are required for
    the plugin to have anything at all to say.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = {}

--[[
    The oldest framework release whose module layout this plugin understands. Read against
    `Constants.Version` from the place; older is not refused, it is reported, because every
    panel already degrades on its own when a module it wants is absent.
]]
Framework.MinimumVersion = "0.2.1"

--- A module required off an Instance. See "untyped on purpose" in the header.
export type Module = any

export type Framework = {
    --- `Constants.Version` as the place reports it.
    Version: string,
    --- The place is older than `Framework.MinimumVersion`.
    Outdated: boolean,
    Constants: Module,
    Selector: Module,
    Presets: Module,
    Adapters: Module,
    --- nil on a framework without `Widgets/Schemas`.
    Schemas: Module?,
    --- nil on a framework without `Tooling/Lint`.
    Lint: Module?,
    --- nil on a framework without `Tooling/Vocab`.
    Vocab: Module?,
    --- The `UnrestManifest` modules whose presets and schemas were registered.
    Manifests: { ModuleScript },
}

--[[
    What every panel is handed besides the framework: the one root they all read, and the three
    things only the host may do -- edit under an undo recording, move Studio's selection, and
    remember a setting between sessions.
]]
export type Context = {
    --- `StarterGui`. Lint scans it, Outline groups it, Vocab is generated from it.
    Root: Instance,
    --- The host's `plugin` global. Panels use it for `GetSetting`/`SetSetting` and nothing else.
    Plugin: Plugin,
    --- Runs `edit` inside one `ChangeHistoryService` recording, so Ctrl+Z undoes all of it.
    Record: (name: string, edit: () -> ()) -> (),
    --- Puts these in Studio's `Selection`, which comes back as a `refresh` on every panel.
    Select: (instances: { Instance }) -> (),
}

--[[
    The contract every panel module satisfies. Documented once in `init.server.luau`, which is
    the only file that mounts one.
]]
export type Panel = {
    --- The selection changed, or something the panel watches did. Redraw from scratch.
    refresh: (selection: { Instance }) -> (),
    --- Drop every connection the panel owns. The host destroys its frame separately.
    destroy: () -> (),
}

export type PanelModule = {
    mount: (parent: Frame, framework: Framework, context: Context) -> Panel,
}

local ABSENT = "Tempat ini tidak memakai Unrest: tidak ada ReplicatedStorage.Unrest, "
    .. "jadi tidak ada tag atau atribut yang bisa dikelola dari sini."

local problem: string = ABSENT
local cached: Framework? = nil
local cachedRoot: Instance? = nil

--[[
    The module at `path` under `container`, or nil when it is absent or refuses to load.

    A require that throws is reported once and treated as absence, because the alternative is a
    plugin that stops drawing every panel over one broken file in the place.
]]
local function load(container: Instance, path: { string }): Module?
    local current: Instance = container
    for _, name in path do
        local child = current:FindFirstChild(name)
        if child == nil then
            return nil
        end
        current = child
    end

    if not current:IsA("ModuleScript") then
        return nil
    end

    local module: ModuleScript = current
    local ok, result = pcall(function(): any
        return require(module) :: any
    end)
    if not ok then
        warn(`[UnrestPlugin] {module:GetFullName()} tidak bisa di-require: {result}`)
        return nil
    end
    return result
end

--- The numbers in a version string, so "0.10.0" sorts after "0.9.0" rather than before it.
local function numbers(version: string): { number }
    local parts: { number } = {}
    for piece in string.gmatch(version, "%d+") do
        table.insert(parts, tonumber(piece) or 0)
    end
    return parts
end

local function older(version: string, than: string): boolean
    local left, right = numbers(version), numbers(than)
    local count = math.max(#left, #right)
    for index = 1, count do
        local a, b = left[index] or 0, right[index] or 0
        if a ~= b then
            return a < b
        end
    end
    return false
end

--[[
    Registers what the place's tagged manifests declare into the plugin's own `Presets` and
    `Schemas`.

    Proposal 2.5: a game's presets and schemas are real only after its bootstrap has run, and
    in edit mode nothing has run. The manifest is the second reader's door -- the same pure
    table the bootstrap registers, found by its tag rather than by a path either side has to
    agree on. Without this the Inspector's `UnrestPreset` dropdown would be empty on every
    place that invented a preset, and `Lint` would warn about names it simply cannot see.

    A manifest that throws on `Register` is skipped: it is data somebody typed, and the finding
    that says so belongs to `Lint`, not to a loader.
]]
local function registerManifests(constants: Module, presets: Module, schemas: Module?): { ModuleScript }
    local found: { ModuleScript } = {}

    for _, tagged in CollectionService:GetTagged(constants.ManifestTag) do
        if not tagged:IsA("ModuleScript") then
            continue
        end
        local module: ModuleScript = tagged
        local ok, manifest = pcall(function(): any
            return require(module) :: any
        end)
        if not ok or typeof(manifest) ~= "table" then
            continue
        end

        table.insert(found, module)

        if typeof(manifest.Presets) == "table" then
            for name, preset in manifest.Presets do
                if typeof(name) == "string" then
                    pcall(presets.Register, name, preset)
                end
            end
        end

        if schemas ~= nil and typeof(manifest.Widgets) == "table" then
            for _, schema in manifest.Widgets do
                pcall(schemas.Register, schema)
            end
        end
    end

    table.sort(found, function(a: ModuleScript, b: ModuleScript): boolean
        return a:GetFullName() < b:GetFullName()
    end)
    return found
end

--[[
    The framework in the open place, or nil when there is none.

    Cached against the `Unrest` instance itself, so inserting the framework into a place that
    did not have it is picked up on the next call while a place that has always had it pays for
    one load. Manifests are re-read every call: a designer can tag one at any moment, and
    registering the same table twice is a replacement, not a duplicate.
]]
function Framework.find(): Framework?
    local unrest = ReplicatedStorage:FindFirstChild("Unrest")
    if unrest == nil then
        cached, cachedRoot = nil, nil
        problem = ABSENT
        return nil
    end

    local existing = cached
    if existing ~= nil and cachedRoot == unrest then
        existing.Manifests = registerManifests(existing.Constants, existing.Presets, existing.Schemas)
        return existing
    end

    local constants = load(unrest, { "Constants" })
    local selector = load(unrest, { "Adapters", "Selector" })
    local presets = load(unrest, { "Presets" })
    local adapters = load(unrest, { "Adapters" })

    if constants == nil or selector == nil or presets == nil or adapters == nil then
        cached, cachedRoot = nil, nil
        problem = "ReplicatedStorage.Unrest ada, tapi Constants, Adapters.Selector, Presets atau Adapters "
            .. "tidak bisa dimuat, jadi plugin tidak punya sumber kebenaran untuk dibaca."
        return nil
    end

    local version = constants.Version
    if typeof(version) ~= "string" then
        version = "?"
    end

    local schemas = load(unrest, { "Widgets", "Schemas" })

    local built: Framework = {
        Version = version,
        Outdated = version ~= "?" and older(version, Framework.MinimumVersion),
        Constants = constants,
        Selector = selector,
        Presets = presets,
        Adapters = adapters.new(),
        Schemas = schemas,
        Lint = load(unrest, { "Tooling", "Lint" }),
        Vocab = load(unrest, { "Tooling", "Vocab" }),
        Manifests = {},
    }
    built.Manifests = registerManifests(constants, presets, schemas)

    cached, cachedRoot = built, unrest
    problem = ABSENT
    return built
end

--- One sentence saying why `find` came back nil. Only meaningful straight after a nil find.
function Framework.explain(): string
    return problem
end

--- The sentence a panel draws when the module it needs is missing from an older framework.
function Framework.needs(module: string): string
    return `Framework di tempat ini belum punya {module}; perbarui ke {Framework.MinimumVersion} atau lebih baru.`
end

return Framework
