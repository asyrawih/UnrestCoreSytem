--!strict
--[[
    Unrest / Net

    What is left of the net layer once the wire is somebody else's problem: the one rule about
    a command *name* that both realms, and every transport, are held to.

    The layer is three jobs that used to be one file:

        Transport   how bytes move          `Net/Transports/Remotes.luau`, or a game's own
        Contracts   what may be asked for   `Net/Contracts.luau`
        Policy      who may ask for it      `Net/Client.luau` (advisory) and the server realm

    Only the first is replaceable. A transport hands the gateway a raw request and the gateway
    decides; the reverse direction would make every new transport a way around the gate. See
    `Net/Transport.luau` for the interface and why it is that small.

    Neither realm's policy lives here -- the client's advisory guard is in `Net/Client.luau`,
    and the real gate is in the server realm, where a client cannot read it.
]]

--- Longest command name the framework will even look at, before any contract lookup. A
--- string is cheap to send and expensive to hash; this bounds that before we care why.
local MAX_COMMAND_LENGTH = 128

local Net = {}

Net.MaxCommandLength = MAX_COMMAND_LENGTH

--[[
    The first thing done to anything arriving off the wire: is this even a command *name*?
    Returns nil for a value that is not a bounded, non-empty string, so every caller below
    can assume it is holding one.

    This runs in the gateway, not in a transport. A transport forwards whatever arrived,
    including a number or a table, precisely so the gateway is the one that calls it
    malformed and counts it against the sender.
]]
function Net.ReadCommand(value: any): string?
    if typeof(value) ~= "string" then
        return nil
    end
    local text = value :: string
    if #text == 0 or #text > MAX_COMMAND_LENGTH then
        return nil
    end
    return text
end

return Net
