--!strict
--[[
    Unrest / Net / Contracts

    The whole security policy of the framework, as data -- and the framework supplies none of
    the data. This module ships with zero commands and zero channels. It owns the *rule*; a
    game owns the *names*.

    A game states its own surface before `Unrest:Start()`:

        local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)

        Contracts:Declare({
            Name = "Example.Action",
            Realm = "Server",
            AllowClient = true,
            Payload = { Kind = "string", MaxLength = 64 },
            RateLimit = { Count = 4, Window = 1 },
            Response = true,
            Description = "What this command does, in one line.",
        })

        Contracts:DeclareChannel({
            Name = "Example.Status",
            Visibility = "Public",
            Value = { Kind = "string", Optional = true, MaxLength = 64 },
        })

    THE RULE, and everything else is a consequence of it:

        A command is unreachable from a client unless its contract sets `AllowClient = true`.

    Not "unless it is marked private". Not "unless a check was added". The absence of an
    opt-in *is* the denial -- and an empty registry is the strongest form of that. Before a
    game declares anything, every name is refused by the client guard and refused again by
    the server gate. Nothing is reachable by default because nothing exists by default.

    Channels follow the same shape with `Visibility`, whose default is `Server`. A channel
    someone forgets to declare does not replicate; it cannot leak by omission.

    THIS TABLE IS REPLICATED, and that is intentional and not a leak: a contract is a list of
    door names and which ones have a handle on the outside. Knowing that a name exists and is
    server-only tells an attacker nothing they can act on, because the lock is in the server
    realm, in code they never receive.

    A note on `Authorize`: these functions are replicated with the declaration, so a client
    can read them. Never close over a secret in one. They may read game state (`player.Character`,
    attributes the server owns) because they only ever *run* on the server -- the copy a
    client holds is inert.

    A note on WHEN to declare: `:Declare` is the only door into the registry, and it must be
    walked through on both realms, because both realms read their own copy of it. Put the
    declarations in a module both bootstraps require, before either starts the framework. A
    command declared on the server but not on the client is simply a command that client
    cannot send; a command declared on the client but not on the server is refused on arrival.
]]

local Net = require(script.Parent.Parent.Net)
local NetTypes = require(script.Parent.Types)

type ArgumentSpec = NetTypes.ArgumentSpec
type CommandContract = NetTypes.CommandContract
type ChannelContract = NetTypes.ChannelContract
type ChannelDeclaration = NetTypes.ChannelDeclaration
type ChannelVisibility = NetTypes.ChannelVisibility

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------

--[[
    Two tables that grow, and nothing else. They are handed out as `Contracts.Commands` and
    `Contracts.Channels` so that tooling can enumerate the declared surface, and they are the
    same tables `:Declare` writes into -- a reader iterating them sees whatever has been
    declared so far rather than a stale copy.

    Each individual contract IS frozen, at declare time. The container is not, because a
    registry that cannot grow is a table, and a table is what this module stopped being. The
    security property never depended on the container being immutable: it depends on the
    client guard and the server gate asking `IsClientCallable` and believing the answer.
]]
local COMMANDS: { [string]: CommandContract } = {}
local CHANNELS: { [string]: ChannelContract } = {}

local REALMS: { [string]: boolean } = table.freeze({ Server = true, Client = true })

local VISIBILITIES: { [string]: boolean } = table.freeze({ Server = true, Player = true, Public = true })

local ARGUMENT_KINDS: { [string]: boolean } = table.freeze({
    string = true,
    number = true,
    integer = true,
    boolean = true,
    ["nil"] = true,
    table = true,
    Vector3 = true,
    Color3 = true,
    EnumItem = true,
})

--------------------------------------------------------------------------------
-- Declaration-time checks
--------------------------------------------------------------------------------

local function fail(message: string): never
    error("[Unrest.Net.Contracts] " .. message, 0)
end

local function sortedNames(source: { [string]: any }): { string }
    local names: { string } = {}
    for name in source do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--- Reads sensibly when the registry is empty, which is the state a game hits first and the
--- one a bare "Declared commands: ." would say nothing about.
local function declaredCommands(): string
    local names = sortedNames(COMMANDS)
    if #names == 0 then
        return "no commands have been declared yet -- call Contracts:Declare before dispatching"
    end
    return "declared commands: " .. table.concat(names, ", ")
end

local function assertOptional(value: any, kind: string, label: string): ()
    if value ~= nil and typeof(value) ~= kind then
        fail(`{label} must be a {kind} or nil, got {typeof(value)}.`)
    end
end

--[[
    A payload schema is walked once, at declare time, so a typo in `Kind` is a startup error
    instead of a command that silently refuses every payload it is ever sent. `seen` is there
    because a spec is an ordinary table a game wrote, and an ordinary table can point at
    itself.
]]
local function assertSpec(spec: any, label: string, seen: { [any]: boolean }): ()
    if typeof(spec) ~= "table" then
        fail(`{label} must be a table describing an ArgumentSpec, got {typeof(spec)}.`)
    end
    if seen[spec] then
        fail(`{label} contains a cycle; an ArgumentSpec must be a finite tree.`)
    end
    seen[spec] = true

    local kind = (spec :: ArgumentSpec).Kind
    if typeof(kind) ~= "string" or not ARGUMENT_KINDS[kind :: string] then
        fail(
            `{label} declares Kind = {tostring(kind)}, which is not an ArgumentKind. `
                .. "Valid kinds: "
                .. table.concat(sortedNames(ARGUMENT_KINDS), ", ")
                .. "."
        )
    end

    local of = (spec :: ArgumentSpec).Of
    if of ~= nil then
        assertSpec(of, `{label}.Of`, seen)
    end

    local fields = (spec :: ArgumentSpec).Fields
    if fields ~= nil then
        if typeof(fields) ~= "table" then
            fail(`{label}.Fields must be a table of name -> ArgumentSpec, got {typeof(fields)}.`)
        end
        for key, field in fields do
            if typeof(key) ~= "string" then
                fail(`{label}.Fields is keyed by {typeof(key)}; field names must be strings.`)
            end
            assertSpec(field, `{label}.Fields.{key}`, seen)
        end
    end

    seen[spec] = nil
end

--- The name a declaration may claim is exactly the name the transport will look at. Keeping
--- the two predicates identical means a game cannot declare a command that no client could
--- ever address.
local function assertName(value: any, what: string): string
    local name = Net.ReadCommand(value)
    if name == nil then
        fail(`a {what} needs a Name that is a string of 1..{Net.MaxCommandLength} characters, got {typeof(value)}.`)
    end
    return name :: string
end

--------------------------------------------------------------------------------

local Contracts = {
    Commands = COMMANDS,
    Channels = CHANNELS,
}

--[[
    Declares a command and returns the frozen contract, so a game can keep the result:

        local Play = Contracts:Declare({ Name = "Example.Action", Realm = "Server" })

    Every consistency rule the old built-in table was checked against at require time is
    checked here instead, per declaration, with the same refusals:

      * `AllowClient` outside the server realm is refused -- a client-callable command must
        run on the server, because there is nowhere else for it to be checked;
      * `Authorize` outside the server realm is refused -- an authorization hook that runs on
        a client is decoration;
      * a second declaration of a name already taken is refused outright rather than merged
        or overwritten. Two declarations of one name means two people believe they own the
        policy for it, and silently keeping one of them is how a `Realm` or an `AllowClient`
        goes quietly missing.
]]
function Contracts:Declare(contract: CommandContract): CommandContract
    if typeof(contract) ~= "table" then
        fail(`:Declare expects a command contract table, got {typeof(contract)}.`)
    end

    local name = assertName((contract :: any).Name, "command")
    if COMMANDS[name] ~= nil then
        fail(
            `"{name}" is already declared. A command name has exactly one contract; `
                .. "declare it once, in the module both realms require."
        )
    end

    local realm = contract.Realm
    if typeof(realm) ~= "string" or not REALMS[realm :: string] then
        fail(`"{name}" declares Realm = {tostring(realm)}; it must be "Server" or "Client".`)
    end

    assertOptional(contract.AllowClient, "boolean", `"{name}".AllowClient`)
    assertOptional(contract.Authorize, "function", `"{name}".Authorize`)
    assertOptional(contract.Response, "boolean", `"{name}".Response`)
    assertOptional(contract.Description, "string", `"{name}".Description`)

    if realm ~= "Server" and contract.AllowClient == true then
        fail(
            `"{name}" is AllowClient but its Realm is "{realm}". `
                .. "A client-callable command must run on the server; there is nowhere else for it to be checked."
        )
    end
    if realm ~= "Server" and contract.Authorize ~= nil then
        fail(
            `"{name}" declares Authorize but does not run on the server. `
                .. "An authorization hook that runs on a client is decoration."
        )
    end

    if contract.Payload ~= nil then
        assertSpec(contract.Payload, `"{name}".Payload`, {})
    end

    local rate = contract.RateLimit
    if rate ~= nil then
        if typeof(rate) ~= "table" then
            fail(`"{name}".RateLimit must be a table of Count and Window, got {typeof(rate)}.`)
        end
        if typeof(rate.Count) ~= "number" or rate.Count ~= rate.Count or rate.Count <= 0 then
            fail(`"{name}".RateLimit.Count must be a positive number, got {tostring(rate.Count)}.`)
        end
        if typeof(rate.Window) ~= "number" or rate.Window ~= rate.Window or rate.Window <= 0 then
            fail(`"{name}".RateLimit.Window must be a positive number of seconds, got {tostring(rate.Window)}.`)
        end
    end

    local frozen = table.freeze(contract)
    COMMANDS[name] = frozen
    return frozen
end

--[[
    Declares a channel and returns the normalised, frozen contract. `Visibility` may be
    omitted; omitting it means `Server`, and that default is applied here rather than by
    everybody remembering it. The declaration type exists so the safe answer is the shortest
    thing to type.

    Like `:Declare`, a repeat declaration is refused: a channel with two visibilities is a
    channel whose audience depends on load order.
]]
function Contracts:DeclareChannel(declaration: ChannelDeclaration): ChannelContract
    if typeof(declaration) ~= "table" then
        fail(`:DeclareChannel expects a channel declaration table, got {typeof(declaration)}.`)
    end

    local name = assertName((declaration :: any).Name, "channel")
    if CHANNELS[name] ~= nil then
        fail(`the channel "{name}" is already declared. Declare it once, in the module both realms require.`)
    end

    local visibility: ChannelVisibility = declaration.Visibility or "Server"
    if not VISIBILITIES[visibility :: string] then
        fail(`the channel "{name}" declares Visibility = {tostring(visibility)}; it must be Server, Player or Public.`)
    end

    assertOptional(declaration.Description, "string", `the channel "{name}".Description`)
    if declaration.Value ~= nil then
        assertSpec(declaration.Value, `the channel "{name}".Value`, {})
    end

    local contract: ChannelContract = table.freeze({
        Name = name,
        Visibility = visibility,
        Value = declaration.Value,
        Description = declaration.Description,
    })
    CHANNELS[name] = contract
    return contract
end

--- Declared command names, sorted. Used by error messages and tooling; a game may use it to
--- assert that its own declarations landed.
function Contracts:List(): { string }
    return sortedNames(COMMANDS)
end

function Contracts:GetCommand(name: string): CommandContract?
    if typeof(name) ~= "string" then
        return nil
    end
    return COMMANDS[name]
end

function Contracts:ExpectCommand(name: string): CommandContract
    local contract = if typeof(name) == "string" then COMMANDS[name] else nil
    if contract == nil then
        error(`[Unrest.Net.Contracts] no command named "{tostring(name)}". {declaredCommands()}.`, 0)
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
    against the server's own copy of the registry. An undeclared name is the same "no" as a
    declared server-only one, which is why an empty registry is closed rather than open.
]]
function Contracts:IsClientCallable(name: string): boolean
    if typeof(name) ~= "string" then
        return false
    end
    local contract = COMMANDS[name]
    return contract ~= nil and contract.AllowClient == true
end

--[[
    The method table is frozen; the two registry tables it points at are not. `table.freeze`
    is shallow, so this pins the API -- nobody replaces `IsClientCallable` with a function
    that says yes -- while leaving the registry able to grow through `:Declare`.
]]
return (table.freeze(Contracts) :: any) :: NetTypes.Contracts
