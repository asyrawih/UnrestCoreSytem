--!strict
--[[
    Unrest / Core

    The Model column of the whiteboard: a registry of systems plus the lifecycle that runs
    them. Core owns state and rules. It never touches Instances -- everything it wants the
    View to know goes out through the Bridge.

    Lifecycle:
      1. `Register` collects definitions (validated by the Resolver).
      2. `Start(unrest)` topologically sorts them by `Dependencies`, runs every `Init(unrest)`
         in that order, then runs every `Start()` in that same order. Two passes means a
         system's `Init` may safely reach for another system's public API, because every
         system exists (if not yet started) by the time any `Start` runs.
      3. `Stop()` runs every `Destroy()` in reverse order.

    Registering after startup is allowed -- that is how `PluginExtended` works. Such a system
    is booted immediately, and its dependencies must already be running.
]]

local Resolver = require(script.Parent.Bridge.Resolver)
local Signal = require(script.Parent.Bridge.Signal)
local Types = require(script.Parent.Types)

local Core = {}

function Core.new(): Types.Core
    local systems: { [string]: Types.System } = {}
    local registrationOrder: { string } = {}
    local booted: { [string]: boolean } = {}
    local isStarted = false
    local root: Types.Unrest? = nil

    local systemAdded: Types.Signal<Types.System> = Signal.new("Core.SystemAdded")

    local core = {
        SystemAdded = systemAdded,
    }

    local function registeredNames(): string
        if #registrationOrder == 0 then
            return "<none>"
        end
        local names = table.clone(registrationOrder)
        table.sort(names)
        return table.concat(names, ", ")
    end

    --- Depth-first topological sort. `chain` exists purely so a cycle can be printed.
    local function resolveOrder(): { Types.System }
        local ordered: { Types.System } = {}
        local visited: { [string]: boolean } = {}
        local visiting: { [string]: boolean } = {}

        local function visit(name: string, chain: { string }, requiredBy: string?)
            if visited[name] then
                return
            end

            if visiting[name] then
                local cycle = table.concat(chain, " -> ") .. " -> " .. name
                error(`[Unrest.Core] dependency cycle: {cycle}.`, 0)
            end

            local system = systems[name]
            if system == nil then
                local blame = if requiredBy ~= nil then `"{requiredBy}" depends on ` else ""
                error(
                    `[Unrest.Core] {blame}"{name}", which is not registered. Registered systems: {registeredNames()}.`,
                    0
                )
            end

            visiting[name] = true
            table.insert(chain, name)

            local dependencies: { string } = system.Dependencies or {}
            for _, dependency in dependencies do
                visit(dependency, chain, name)
            end

            table.remove(chain)
            visiting[name] = nil
            visited[name] = true
            table.insert(ordered, system)
        end

        for _, name in registrationOrder do
            visit(name, {}, nil)
        end

        return ordered
    end

    local function boot(system: Types.System): ()
        local init = system.Init
        if init ~= nil then
            init(system, root :: Types.Unrest)
        end
        local start = system.Start
        if start ~= nil then
            start(system)
        end
        booted[system.Name] = true
    end

    function core:Register(definition: Types.System): Types.System
        local system = Resolver.System(definition)

        if systems[system.Name] ~= nil then
            error(
                `[Unrest.Core] a system named "{system.Name}" is already registered. `
                    .. "System names are the registry keys and must be unique.",
                0
            )
        end

        systems[system.Name] = system
        table.insert(registrationOrder, system.Name)

        if isStarted then
            -- Late registration (plugins). Dependencies must already be running.
            local dependencies: { string } = system.Dependencies or {}
            for _, dependency in dependencies do
                if not booted[dependency] then
                    systems[system.Name] = nil
                    table.remove(registrationOrder, #registrationOrder)
                    error(
                        `[Unrest.Core] "{system.Name}" was registered after startup but depends on "{dependency}", `
                            .. "which is not running. Register it before Unrest:Start(), or register its "
                            .. "dependency first.",
                        0
                    )
                end
            end
            boot(system)
        end

        systemAdded:Fire(system)
        return system
    end

    function core:Get(name: string): Types.System?
        return systems[name]
    end

    function core:Expect(name: string): Types.System
        local system = systems[name]
        if system == nil then
            error(`[Unrest.Core] no system named "{name}". Registered systems: {registeredNames()}.`, 0)
        end
        return system
    end

    function core:Has(name: string): boolean
        return systems[name] ~= nil
    end

    function core:List(): { string }
        local names: { string } = {}
        for _, system in resolveOrder() do
            table.insert(names, system.Name)
        end
        return names
    end

    function core:Start(unrest: Types.Unrest): ()
        if isStarted then
            error("[Unrest.Core] :Start() was called twice. Unrest boots once per runtime context.", 0)
        end

        root = unrest
        local ordered = resolveOrder()
        isStarted = true

        for _, system in ordered do
            local init = system.Init
            if init ~= nil then
                init(system, unrest)
            end
        end

        for _, system in ordered do
            local start = system.Start
            if start ~= nil then
                start(system)
            end
            booted[system.Name] = true
        end
    end

    function core:Stop(): ()
        if not isStarted then
            return
        end
        isStarted = false

        local ordered = resolveOrder()
        for index = #ordered, 1, -1 do
            local system = ordered[index]
            local teardown = system.Destroy
            if teardown ~= nil then
                teardown(system)
            end
            booted[system.Name] = false
        end

        root = nil
    end

    function core:IsStarted(): boolean
        return isStarted
    end

    return (core :: any) :: Types.Core
end

return Core
