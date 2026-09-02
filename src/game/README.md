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

Names are reachable only through the module that already declared them, so "dispatched a
command nobody declared" is not a shape this codebase has.
