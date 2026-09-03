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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNetMax = require(ReplicatedStorage.Packages.ByteNet)

--[[
    The game's wire format, shared by both realms so their packet ids agree.

    ONE PACKET PER MESSAGE, not a generic envelope. That is the point of ByteNet: a concrete
    schema that packs. A generic envelope would need `ByteNet.unknown`, which packs nothing and
    passes the value alongside the buffer as an ordinary remote argument.

    THE PRICE, stated plainly. A generic remote carried the channel name in the message, so one
    mapping covered every label in the game and a new channel cost two attributes in Studio.
    Now a new channel means a new packet here plus one mapping in the client.

    UPSTREAM BUG. `bytenet-max@1.0.0` cannot be required as published: `namespaces/namespace`
    and `dataTypes/struct` both ask for `namespacesDependencies` while the file is called
    `namespaceDependencies`, one letter apart, and the entry point requires both. The copy in
    `Packages/` is patched by hand, which Wally will overwrite on the next install.
]]

return ByteNetMax.defineNamespace("Game", function()
    return {
        packets = {
            Beli = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Barang = ByteNetMax.string }),
            }),

            Koin = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Nilai = ByteNetMax.uint32 }),
            }),

            Pesan = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Teks = ByteNetMax.string }),
            }),

            --[[
                The server directory, server -> client. One message carries the whole list
                because that is what the panel draws: a partial list is not a smaller list,
                it is a wrong one.

                `Users` is `float64`, not `uint32`. Roblox user ids passed 2^32 in 2024, so a
                `uint32` would silently wrap the newest accounts into somebody else's id --
                the kind of bug that only shows up for the players who joined most recently.
                `float64` holds every integer up to 2^53 exactly.

                `Players` and `Capacity` are `uint8`, which caps a server at 255 seats. That
                is above every real `Players.MaxPlayers`, and the sender clamps rather than
                trusting it.
            ]]
            ServerList = ByteNetMax.definePacket({
                value = ByteNetMax.struct({
                    Servers = ByteNetMax.array(ByteNetMax.struct({
                        JobId = ByteNetMax.string,
                        Players = ByteNetMax.uint8,
                        Capacity = ByteNetMax.uint8,
                        Users = ByteNetMax.array(ByteNetMax.float64),
                    })),
                }),
            }),

            --[[
                "Send me the list", client -> server, carrying nothing at all: the request has
                no content beyond having been made, and the sender is the second argument
                Roblox fills in rather than anything the message could claim.

                It exists so the client can ask once when it is ready to listen, rather than
                the server guessing when that is. The answer comes out of a cache the poll
                loop fills, so a player mashing Refresh cannot reach MemoryStore.
            ]]
            ServerListRequest = ByteNetMax.definePacket({
                value = ByteNetMax.nothing,
            }),
        },
    }
end)
