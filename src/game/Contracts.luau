--!strict
--[[
    Game / Contracts

    This game's security policy, as data, declared into the framework's registry.

    Requiring this module IS the declaration. There is no `:Init()` to forget and no order to
    get wrong: the calls below run once, at require time, in whichever realm required it. Both
    bootstraps require `ReplicatedStorage.Game` before they start anything, so by the time a
    handler is registered or a button is clicked the registry is already closed over the exact
    set of commands this game has.

    If a bootstrap ever forgets, the framework fails CLOSED, twice over: the client guard
    refuses to send a command it cannot find a contract for, and the server gateway refuses it
    again on arrival. A missing require produces a loud refusal, never an open door.

    THE RULE, and everything else is a consequence of it:

        A command is unreachable from a client unless its contract sets `AllowClient = true`.

    Not "unless it is marked private". Not "unless a check was added". The absence of an
    opt-in *is* the denial. Adding a name to `Names.luau` grants nothing at all; only a
    `Declare` call with `AllowClient = true` does. `Music.ForceStopAll` and `Plugin.Reload`
    below are the worked examples: ordinary commands that server code dispatches freely, which
    no client can reach, because nobody wrote one extra line.

    Channels follow the same shape with `Visibility`, whose default is `Server`. A channel
    nobody declares does not replicate; it cannot leak by omission.

    A note on `Authorize`: this module lives in ReplicatedStorage, so a client can read these
    functions. Never close over a secret here. They may read game state (`player.Character`,
    attributes the server owns) because they only ever *run* on the server -- the copy a client
    holds is inert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
local Names = require(script.Parent.Names)
local UnrestTypes = require(ReplicatedStorage.Unrest.Types)

type ArgumentSpec = UnrestTypes.ArgumentSpec

local CHANNELS = Names.Channels
local COMMANDS = Names.Commands

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

Contracts:Declare({
    Name = COMMANDS.MusicPlay,
    Realm = "Server",
    AllowClient = true,
    Payload = IDENTIFIER,
    RateLimit = { Count = 4, Window = 1 },
    Response = true,
    Description = "Play a registered track by name. Returns false for an unknown track.",
})

Contracts:Declare({
    Name = COMMANDS.MusicStop,
    Realm = "Server",
    AllowClient = true,
    -- No `Payload`, so this command accepts nil and nothing else.
    RateLimit = { Count = 4, Window = 1 },
    Description = "Stop the current track.",
})

Contracts:Declare({
    Name = COMMANDS.MusicSetVolume,
    Realm = "Server",
    AllowClient = true,
    Payload = UNIT_INTERVAL,
    --[[
        Volume is shared state: one player's slider is heard by everyone. It is
        client-callable because this game wants a command that writes global state through the
        gate, and it is rate limited hard for exactly that reason. Tightening it means adding
        an `Authorize` line here -- see `Dance.Play` for the shape -- and the point of a
        contract is that doing so is a one-line change in one file, with no handler, UI, or
        transport code to touch.
    ]]
    RateLimit = { Count = 8, Window = 1 },
    Description = "Set the master music volume, 0..1.",
})

--[[
    SERVER-ONLY, WORKED EXAMPLE #1.

    Note what is *not* here: there is no `AllowClient`, and there is no "Private = true"
    either. The command is unreachable from a client because nobody opted it in. Server code
    dispatches it like any other command; a client that sends its name gets
    `NotClientCallable` from the gateway, having learned nothing.
]]
Contracts:Declare({
    Name = COMMANDS.MusicForceStopAll,
    Realm = "Server",
    Description = "Operator command: silence the soundtrack and clear the now-playing state.",
})

Contracts:Declare({
    Name = COMMANDS.DancePlay,
    Realm = "Server",
    AllowClient = true,
    Payload = IDENTIFIER,
    RateLimit = { Count = 3, Window = 2 },
    Authorize = hasLivingCharacter,
    Response = true,
    Description = "Play a named emote on the calling player's own character.",
})

Contracts:Declare({
    Name = COMMANDS.DanceStop,
    Realm = "Server",
    AllowClient = true,
    RateLimit = { Count = 3, Window = 2 },
    Description = "Stop the calling player's emote.",
})

--- SERVER-ONLY, WORKED EXAMPLE #2. Reloading plugin modules is an operator action; a client
--- asking for it would be asking the server to re-execute arbitrary ModuleScripts.
Contracts:Declare({
    Name = COMMANDS.PluginReload,
    Realm = "Server",
    Response = true,
    Description = "Operator command: re-scan the plugin folder and register anything new.",
})

--------------------------------------------------------------------------------
-- Channels
--------------------------------------------------------------------------------

Contracts:DeclareChannel({
    Name = CHANNELS.NowPlaying,
    Visibility = "Public",
    Value = OPTIONAL_IDENTIFIER,
    Description = "The track everyone is hearing, or nil for silence.",
})

Contracts:DeclareChannel({
    Name = CHANNELS.MusicVolume,
    Visibility = "Public",
    Value = UNIT_INTERVAL,
    Description = "Master music volume, 0..1.",
})

--[[
    `Player` visibility: one player's own emote is their business and nobody else's, so the
    value is addressed rather than broadcast. A `Player` channel is never retained server-side
    either -- there is no single "current value" of a per-player channel, and pretending
    otherwise would let one player's state be read as everyone's.
]]
Contracts:DeclareChannel({
    Name = CHANNELS.Dance,
    Visibility = "Player",
    Value = OPTIONAL_IDENTIFIER,
    Description = "The emote the receiving player is performing, or nil.",
})

--[[
    `Player`, carrying the character's NAME and not the character. The schema is what enforces
    that: a Model is an Instance, an Instance is not plain data, and validation refuses it. The
    authoritative Model stays in AvatarContext's own table on the server, where a live
    reference into the data model belongs.
]]
Contracts:DeclareChannel({
    Name = CHANNELS.Character,
    Visibility = "Player",
    Value = { Kind = "string", Optional = true, MaxLength = 64 },
    Description = "The receiving player's character name while it is loaded, or nil.",
})

--[[
    WORKED EXAMPLE of the channel default: no `Visibility` line at all, so this is `Server` and
    never replicates. Which plugins a server loaded is its own business, and the safe answer is
    the one you get by not thinking about it.
]]
Contracts:DeclareChannel({
    Name = CHANNELS.Plugins,
    Description = "Names of the systems registered through PluginExtended. Server-side only.",
})

--------------------------------------------------------------------------------

--[[
    Declaring is the point; there is nothing to hand back. Read the registry through
    `Unrest.Bridge.Contracts` (or `Contracts:List()`) rather than through this module, so
    there is one answer to "what is declared" and it is the framework's.
]]
return table.freeze({})
