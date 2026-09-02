--!strict
--[[
    Unrest / Core / Systems / PluginExtended

    The whiteboard's "Plugin Extended" box: the supported way to grow the Model layer without
    editing the framework.

    A plugin is just a system table -- the exact same contract the built-ins use. Register one
    by hand, or drop ModuleScripts into a folder and hand the folder over. Because Core allows
    registration after startup, plugins loaded at any point are initialised and started
    immediately; their dependencies simply have to already be running.
]]

local Types = require(script.Parent.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Parent.Constants)
local Signal = require(script.Parent.Parent.Parent.Bridge.Signal)

local PluginExtended = {
    Name = "PluginExtended",

    PluginAdded = (Signal.new("PluginExtended.PluginAdded") :: any) :: Types.Signal<Types.System>,

    _registered = {} :: { string },
    _unrest = nil :: Types.Unrest?,
}

function PluginExtended:List(): { string }
    return table.clone(self._registered)
end

function PluginExtended:_publish(): ()
    local unrest = self._unrest
    if unrest == nil then
        return
    end
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
    Requires every ModuleScript child of `container` and registers whatever it returns.
    A module that throws, or returns something that is not a system table, is reported by
    name and skipped -- one bad plugin must not take the whole game down.
]]
function PluginExtended:LoadFromFolder(container: Instance): { Types.System }
    if typeof(container) ~= "Instance" then
        error(`[Unrest.PluginExtended] :LoadFromFolder expects an Instance, got {typeof(container)}.`, 0)
    end

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
end

function PluginExtended:Start(): ()
    self:_publish()
end

function PluginExtended:Destroy(): ()
    table.clear(self._registered)
    self._unrest = nil
end

return PluginExtended
