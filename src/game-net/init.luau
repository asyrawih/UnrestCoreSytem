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
        },
    }
end)
