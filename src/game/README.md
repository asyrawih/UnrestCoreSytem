# src/game — ReplicatedStorage.Game

Game content that both realms need to read.

The framework knows nothing about this folder. It is mounted beside
`ReplicatedStorage.Unrest`, not inside it, and nothing under `src/shared` may ever require
anything here. The dependency runs one way only: game code requires the framework.

What lives here is everything the client and the server must agree on but the framework must
not contain:

  * the names of this game's channels and commands;
  * the contract for each one, declared into the framework's registry;
  * the preset bundles a designer names in Studio.

Declaring is a side effect of requiring. Both bootstraps require this folder early, and if one
of them forgets, the framework fails closed: an undeclared command is refused by the client
guard and refused again by the server gateway.

## The files

| File | What it is |
| --- | --- |
| `init.luau` | The front door. Requiring it declares everything below and hands back `Channels` and `Commands`. Both bootstraps require this and nothing else. |
| `Names.luau` | The channel and command names, spelled once. |
| `Contracts.luau` | `Contracts:Declare` / `:DeclareChannel` for every one of them. Required for the side effect. |
| `Presets.luau` | `Presets.Register` for each attribute bundle. Required for the side effect. |
| `Types.luau` | The shapes of this game's systems: `Track`, `MusicSystem`, `AvatarContext`, `DanceSystem`, `PluginExtended`. |
| `Packets.luau` | **This game's wire format**: three ByteNet envelopes and the payload codec. Required by `Transport.luau` and by nothing else. |
| `Transport.luau` | **The ByteNet transport**, as a `TransportProvider`. Returns the provider itself, so installing it is one line. |

Names are reachable only through the module that already declared them, so "dispatched a
command nobody declared" is not a shape this codebase has.

## The transport

`Transport.luau` and `Packets.luau` are the user-owned half of the network seam. The framework
carries requests through `Unrest.Net.Transport`'s ten methods and never learns which library is
underneath; these two files are the library.

`init.luau` deliberately does **not** require them. The `Packages` mount is optional, so a
require here would make a missing ByteNet break every command in the game rather than just the
transport that needs it. Installing it is an explicit line in a bootstrap instead:

```luau
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))
```

The envelope is generic -- one `Request` packet carrying a command name and an opaque payload
buffer -- so declaring a command costs nothing on the wire. Typed packets per command are the
optimisation after that, and the place they would be declared is the `Wire` field on the
command's own contract, next to the policy that governs it.
