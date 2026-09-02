--!strict
--[[
    Unrest / Net / Contracts

    The whole security policy of the framework, as data, in one screenful.

    This table lives in ReplicatedStorage, which means every client can read it. That is
    intentional and it is not a leak: a contract is a list of door names and which ones have a
    handle on the outside. Knowing the name `Music.ForceStopAll` and that it is server-only
    tells an attacker nothing they can act on, because the lock is in the server realm, in
    code they never receive.

    THE RULE, and everything else is a consequence of it:

        A command is unreachable from a client unless its contract sets `AllowClient = true`.

    Not "unless it is marked private". Not "unless a check was added". The absence of an
    opt-in *is* the denial. Adding a name to `Constants.Commands` grants nothing at all; only
    a row in this table with `AllowClient = true` does. `Music.ForceStopAll` and
    `Plugin.Reload` below are the worked examples: they are ordinary commands that server code
    dispatches freely, and no client can reach them, because nobody wrote one extra line.

    Channels follow the same shape with `Visibility`, whose default is `Server`. A channel
    someone forgets to declare does not replicate; it cannot leak by omission.

    A note on `Authorize`: these functions are replicated with this module, so a client can
    read them. Never close over a secret here. They may read game state (`player.Character`,
    attributes the server owns) because they only ever *run* on the server -- the copy a
    client holds is inert.
]]

local Constants = require(script.Parent.Parent.Constants)
local NetTypes = require(script.Parent.Types)

type ArgumentSpec = NetTypes.ArgumentSpec
type CommandContract = NetTypes.CommandContract
type ChannelContract = NetTypes.ChannelContract
type ChannelVisibility = NetTypes.ChannelVisibility

--[[
    A channel as it is written below: `Visibility` may be omitted. Omitting it means `Server`,
    and that is enforced by `normaliseChannels` rather than by everybody remembering. The
    declaration type exists so the safe default is the *shortest* thing to type.
]]
type ChannelDeclaration = {
    Name: string,
    Visibility: ChannelVisibility?,
    Value: ArgumentSpec?,
    Description: string?,
}

--------------------------------------------------------------------------------
-- Reusable schemas
--------------------------------------------------------------------------------

--- Track and dance names are identifiers chosen by the game, never free text. Constraining
--- them to a pattern means a payload can never carry a newline, a control character, or the
--- 200KB string somebody hoped would end up in a log line.
local IDENTIFIER: ArgumentSpec = {
    Kind = "string",
    MaxLength = 64,
    Pattern = "[%w_%-%.]+",
}

local OPTIONAL_IDENTIFIER: ArgumentSpec = {
    Kind = "string",
    Optional = true,
    MaxLength = 64,
    Pattern = "[%w_%-%.]+",
}

local UNIT_INTERVAL: ArgumentSpec = {
    Kind = "number",
    Min = 0,
    Max = 1,
}

--------------------------------------------------------------------------------
-- Authorize hooks
--------------------------------------------------------------------------------

--[[
    The last gate, and the only one that can see the game rather than the message. Runs on the
    server after the schema and rate checks, so it is allowed to assume a well-formed payload
    and to do slightly more work than a per-request check normally could.

    Its refusal reason is logged on the server and never sent back. A client that probes
    `Dance.Play` learns only `Unauthorized`; it cannot tell "you are dead" from "you are not
    loaded" from "that emote is staff-only", so it cannot map the inside of the server by
    watching which lies fail differently.
]]
local function hasLivingCharacter(player: Player, _payload: any): (boolean, string?)
    local character = player.Character
    if character == nil then
        return false, "the player has no character loaded"
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        return false, "the player's character has no Humanoid"
    end
    if humanoid.Health <= 0 then
        return false, "the player is dead"
    end

    return true, nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local COMMANDS: { [string]: CommandContract } = {
    [Constants.Commands.MusicPlay] = {
        Name = Constants.Commands.MusicPlay,
        Realm = "Server",
        AllowClient = true,
        Payload = IDENTIFIER,
        RateLimit = { Count = 4, Window = 1 },
        Response = true,
        Description = "Play a registered track by name. Returns false for an unknown track.",
    },

    [Constants.Commands.MusicStop] = {
        Name = Constants.Commands.MusicStop,
        Realm = "Server",
        AllowClient = true,
        -- No `Payload`, so this command accepts nil and nothing else.
        RateLimit = { Count = 4, Window = 1 },
        Description = "Stop the current track.",
    },

    [Constants.Commands.MusicSetVolume] = {
        Name = Constants.Commands.MusicSetVolume,
        Realm = "Server",
        AllowClient = true,
        Payload = UNIT_INTERVAL,
        --[[
            Volume is shared state: one player's slider is heard by everyone. It is
            client-callable because the framework's demo needs a command that writes global
            state through the gate, and it is rate limited hard for exactly that reason. A
            shipping game adds an `Authorize` here -- see `Dance.Play` for the shape -- and
            the point of the contract table is that doing so is a one-line change in one file,
            with no handler, UI, or transport code to touch.
        ]]
        RateLimit = { Count = 8, Window = 1 },
        Description = "Set the master music volume, 0..1.",
    },

    --[[
        SERVER-ONLY, WORKED EXAMPLE #1.

        Note what is *not* here: there is no `AllowClient`, and there is no "Private = true"
        either. The command is unreachable from a client because nobody opted it in. Server
        code dispatches it like any other command; a client that sends its name gets
        `NotClientCallable` from the gateway, having learned nothing.
    ]]
    [Constants.Commands.MusicForceStopAll] = {
        Name = Constants.Commands.MusicForceStopAll,
        Realm = "Server",
        Description = "Operator command: silence the soundtrack and clear the now-playing state.",
    },

    [Constants.Commands.DancePlay] = {
        Name = Constants.Commands.DancePlay,
        Realm = "Server",
        AllowClient = true,
        Payload = IDENTIFIER,
        RateLimit = { Count = 3, Window = 2 },
        Authorize = hasLivingCharacter,
        Response = true,
        Description = "Play a named emote on the calling player's own character.",
    },

    [Constants.Commands.DanceStop] = {
        Name = Constants.Commands.DanceStop,
        Realm = "Server",
        AllowClient = true,
        RateLimit = { Count = 3, Window = 2 },
        Description = "Stop the calling player's emote.",
    },

    --- SERVER-ONLY, WORKED EXAMPLE #2. Reloading plugin modules is an operator action; a
    --- client asking for it would be asking the server to re-execute arbitrary ModuleScripts.
    [Constants.Commands.PluginReload] = {
        Name = Constants.Commands.PluginReload,
        Realm = "Server",
        Response = true,
        Description = "Operator command: re-scan the plugin folder and register anything new.",
    },
}

--------------------------------------------------------------------------------
-- Channels
--------------------------------------------------------------------------------

local CHANNEL_DECLARATIONS: { [string]: ChannelDeclaration } = {
    [Constants.Channels.NowPlaying] = {
        Name = Constants.Channels.NowPlaying,
        Visibility = "Public",
        Value = OPTIONAL_IDENTIFIER,
        Description = "The track everyone is hearing, or nil for silence.",
    },

    [Constants.Channels.MusicVolume] = {
        Name = Constants.Channels.MusicVolume,
        Visibility = "Public",
        Value = UNIT_INTERVAL,
        Description = "Master music volume, 0..1.",
    },

    --[[
        `Player` visibility: one player's own emote is their business and nobody else's, so
        the value is addressed rather than broadcast. A `Player` channel is never retained
        server-side either -- there is no single "current value" of a per-player channel, and
        pretending otherwise would let one player's state be read as everyone's.
    ]]
    [Constants.Channels.Dance] = {
        Name = Constants.Channels.Dance,
        Visibility = "Player",
        Value = OPTIONAL_IDENTIFIER,
        Description = "The emote the receiving player is performing, or nil.",
    },

    --[[
        `Player`, carrying the character's NAME and not the character. The schema is what
        enforces that: a Model is an Instance, an Instance is not plain data, and validation
        refuses it. The authoritative Model stays in AvatarContext's own table on the server,
        where a live reference into the data model belongs.
    ]]
    [Constants.Channels.Character] = {
        Name = Constants.Channels.Character,
        Visibility = "Player",
        Value = { Kind = "string", Optional = true, MaxLength = 64 },
        Description = "The receiving player's character name while it is loaded, or nil.",
    },

    --[[
        WORKED EXAMPLE of the channel default: no `Visibility` line at all, so this is
        `Server` and never replicates. Which plugins a server loaded is its own business, and
        the safe answer is the one you get by not thinking about it.
    ]]
    [Constants.Channels.Plugins] = {
        Name = Constants.Channels.Plugins,
        Description = "Names of the systems registered through PluginExtended. Server-side only.",
    },
}

local function normaliseChannels(declarations: { [string]: ChannelDeclaration }): { [string]: ChannelContract }
    local channels: { [string]: ChannelContract } = {}
    for key, declaration in declarations do
        -- The default is applied here, once, rather than being remembered per channel.
        local visibility: ChannelVisibility = declaration.Visibility or "Server"
        channels[key] = table.freeze({
            Name = declaration.Name,
            Visibility = visibility,
            Value = declaration.Value,
            Description = declaration.Description,
        })
    end
    return table.freeze(channels)
end

local CHANNELS = normaliseChannels(CHANNEL_DECLARATIONS)

--------------------------------------------------------------------------------
-- Self-consistency, checked once at require time
--------------------------------------------------------------------------------

for key, contract in COMMANDS do
    table.freeze(contract)
    if contract.Name ~= key then
        error(`[Unrest.Net.Contracts] the command keyed "{key}" declares Name = "{contract.Name}".`, 0)
    end
    if contract.Realm ~= "Server" and contract.AllowClient == true then
        error(
            `[Unrest.Net.Contracts] "{key}" is AllowClient but its Realm is "{contract.Realm}". `
                .. "A client-callable command must run on the server; there is nowhere else for it to be checked.",
            0
        )
    end
    if contract.Realm ~= "Server" and contract.Authorize ~= nil then
        error(
            `[Unrest.Net.Contracts] "{key}" declares Authorize but does not run on the server. `
                .. "An authorization hook that runs on a client is decoration.",
            0
        )
    end
end

for key, contract in CHANNELS do
    if contract.Name ~= key then
        error(`[Unrest.Net.Contracts] the channel keyed "{key}" declares Name = "{contract.Name}".`, 0)
    end
end

--------------------------------------------------------------------------------

local function declaredCommands(): string
    local names: { string } = {}
    for name in COMMANDS do
        table.insert(names, name)
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local Contracts = {
    Commands = table.freeze(COMMANDS),
    Channels = CHANNELS,
}

function Contracts:GetCommand(name: string): CommandContract?
    if typeof(name) ~= "string" then
        return nil
    end
    return COMMANDS[name]
end

function Contracts:ExpectCommand(name: string): CommandContract
    local contract = if typeof(name) == "string" then COMMANDS[name] else nil
    if contract == nil then
        error(`[Unrest.Net.Contracts] no command named "{tostring(name)}". Declared commands: {declaredCommands()}.`, 0)
    end
    return contract
end

function Contracts:GetChannel(name: string): ChannelContract?
    if typeof(name) ~= "string" then
        return nil
    end
    return CHANNELS[name]
end

--[[
    The single question both sides ask, and the reason the answer cannot be argued with:
    there is no third state. No contract, or a contract that never says `AllowClient = true`,
    is a no. Nothing in a request is consulted to compute this -- only the name, and only
    against the server's own copy of the table.
]]
function Contracts:IsClientCallable(name: string): boolean
    if typeof(name) ~= "string" then
        return false
    end
    local contract = COMMANDS[name]
    return contract ~= nil and contract.AllowClient == true
end

return (table.freeze(Contracts) :: any) :: NetTypes.Contracts
