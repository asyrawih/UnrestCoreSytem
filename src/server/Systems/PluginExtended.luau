--!strict
--[[
    Unrest / Server / Systems / PluginExtended

    The whiteboard's "Plugin Extended" box: the supported way to grow the Model layer without
    editing the framework.

    A plugin is just a system table -- the exact same contract the built-ins use. Register one
    by hand, or drop ModuleScripts into a folder and hand the folder over. Because Core allows
    registration after startup, plugins loaded at any point are initialised and started
    immediately; their dependencies simply have to already be running.

    TWO SECURITY NOTES, both of which are contract lines rather than code:

      * `Plugin.Reload` re-executes ModuleScripts on the server. It is a server-only command --
        no `AllowClient` in its contract -- because a client that could ask for it would be
        asking the server to run code on demand.

      * `Plugin.Registered` is a `Server` channel, which it becomes by having no `Visibility`
        line at all. Which plugins a server loaded is its own business, and the safe answer is
        the one you get by not thinking about it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Maid = require(ReplicatedStorage.Unrest.Util.Maid)
local Signal = require(ReplicatedStorage.Unrest.Util.Signal)
local Types = require(ReplicatedStorage.Unrest.Types)

local PluginExtended = {
    Name = "PluginExtended",
    Dependencies = {} :: { string },

    PluginAdded = (Signal.new("PluginExtended.PluginAdded") :: any) :: Types.Signal<Types.System>,

    _registered = {} :: { string },
    _container = nil :: Instance?,
    _unrest = nil :: Types.Unrest?,
    _maid = Maid.new(),
}

function PluginExtended:List(): { string }
    return table.clone(self._registered)
end

function PluginExtended:_publish(): ()
    local unrest = self._unrest
    if unrest == nil then
        return
    end
    -- Stays on the server: the channel's contract declares no Visibility, so it is `Server`.
    unrest.Bridge:Publish(Constants.Channels.Plugins, self:List())
end

--- Registers a third-party system. Validation and duplicate detection live in Core.
function PluginExtended:Register(definition: Types.System): Types.System
    local unrest = self._unrest
    if unrest == nil then
        error(
            "[Unrest.PluginExtended] :Register was called before Unrest:Start(). "
                .. "Register plugins from a bootstrap script, or via Unrest.Core:Register directly.",
            0
        )
    end

    local system = unrest.Core:Register(definition)
    table.insert(self._registered, system.Name)
    self.PluginAdded:Fire(system)
    self:_publish()

    return system
end

--[[
    Requires every ModuleScript child of `container` and registers whatever it returns. A module
    that throws, or returns something that is not a system table, is reported by name and
    skipped -- one bad plugin must not take the whole game down.
]]
function PluginExtended:LoadFromFolder(container: Instance): { Types.System }
    if typeof(container) ~= "Instance" then
        error(`[Unrest.PluginExtended] :LoadFromFolder expects an Instance, got {typeof(container)}.`, 0)
    end

    -- Remembered so `Plugin.Reload` has somewhere to reload from.
    self._container = container

    local loaded: { Types.System } = {}

    for _, child in container:GetChildren() do
        if not child:IsA("ModuleScript") then
            continue
        end

        local ok, result = pcall(require, child)
        if not ok then
            warn(`[Unrest.PluginExtended] {child:GetFullName()} errored while loading: {tostring(result)}`)
            continue
        end

        local registered, err = pcall(function()
            return self:Register(result :: any)
        end)
        if not registered then
            warn(`[Unrest.PluginExtended] {child:GetFullName()} is not a valid system: {tostring(err)}`)
            continue
        end

        table.insert(loaded, err :: any)
    end

    return loaded
end

function PluginExtended:Init(unrest: Types.Unrest): ()
    self._unrest = unrest

    --[[
        A server-only command handler, registered through the Bridge exactly like a
        client-callable one. The difference between this and `Music.Play` is one line in
        `Net/Contracts.luau` and nothing whatsoever here.
    ]]
    self._maid:Add(unrest.Bridge:Handle(Constants.Commands.PluginReload, function(): number
        local container = self._container
        if container == nil then
            warn("[Unrest.PluginExtended] Plugin.Reload was dispatched but no folder has been loaded yet.")
            return 0
        end
        return #self:LoadFromFolder(container)
    end))
end

function PluginExtended:Start(): ()
    self:_publish()
end

function PluginExtended:Destroy(): ()
    table.clear(self._registered)
    self._container = nil
    self._unrest = nil
    self._maid:Destroy()
end

return PluginExtended
