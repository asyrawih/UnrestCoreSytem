# UnrestCoreSystem — Architecture

A Model/View/Controller framework for Roblox, built around two rules.

**The framework builds no UI.** Every element is made by hand in Roblox Studio. Tagging an
instance `Unrest` is the entire opt-in: it is adopted, an adapter is resolved for its
ClassName, its `Unrest*` attributes are wired, and it becomes visible to `Unrest:Query`.
Untagging releases it. There are no components, no `Mount`, and nothing in
ReplicatedStorage that draws a button.

**A command is unreachable from a client unless its contract says otherwise.** The client
guard and the server gate read the same contract, and the server never trusts the client's
copy of it. Adding a name to `Constants.Commands` grants nothing.

```
   Core (Model)              Bridge (Controller)              View
  ┌──────────────┐          ┌───────────────────┐      ┌──────────────────┐
  │ MusicSystem  │          │  Publish/Subscribe│      │  UI built in     │
  │ AvatarContext│  ──────► │  Dispatch/Invoke  │ ───► │  Studio, tagged  │
  │ DanceSystem  │          │  Handle           │      │  `Unrest`        │
  │ PluginExtend │          ├───────────────────┤      └──────────────────┘
  └──────────────┘          │  Net: contracts,  │              ▲
   authoritative,           │  validation,      │              │
   server realm             │  rate limits      │      CollectionService
                            └───────────────────┘       adoption + adapters
```

Core never touches an Instance. Adopted UI never touches a system. Everything crosses at
the Bridge, and the Bridge asks the contracts what is allowed.

## 1. Layer contract

| Layer | Lives in | May depend on | Never |
| --- | --- | --- | --- |
| `Primitives` | ReplicatedStorage | nothing | — |
| `Util` (Signal, Maid, Resolver) | ReplicatedStorage | Primitives | game state |
| `Core` | registry shared, systems on the server | Bridge, Util | Instances, UI, players' screens |
| `Bridge` | ReplicatedStorage | Net, Util | knowing what a button is |
| `Net` | contracts shared, gateway server-only | Bridge types, Constants | trusting a payload |
| `Adapters` | ReplicatedStorage | Primitives | game logic |
| `Elements` | ReplicatedStorage, client-only at runtime | Adapters, Bridge | calling a system directly |

Two module boundaries are load-bearing:

**Contracts are public, locks are not.** `Net/Contracts.luau` sits in ReplicatedStorage
where any client can read it. That is intended. It is a list of door names and which ones
have a handle on the outside; the locks are the server gateway, which lives in
ServerScriptService and never replicates.

**Systems are server-side.** The Core *registry* is shared machinery, but the systems that
hold authoritative state live in `src/server/Systems/`. A client cannot read them, so it
cannot learn from them or call into them except through a declared command.

## 2. Adoption — how Studio UI enters the framework

A designer builds the interface normally. The only framework-facing act is adding the
`Unrest` tag. On adoption:

1. **An adapter is resolved.** The registry picks the most specific adapter the instance
   `:IsA()`, then flattens its `Extends` chain, so `TextButton` inherits everything
   `GuiButton` and `GuiObject` declare. The result is cached per ClassName.
2. **Attributes are wired.** The `Unrest*` attributes below turn into live behavior, and
   re-wire when they change.
3. **The element becomes queryable.** Any existing `Unrest:Query` whose descriptor now
   matches picks it up immediately — queries are live bindings, not one-shot scans.

Adoption is client-only. A tagged ScreenGui does exist on the server, but binding its
events there would be both useless and misleading: **a UI event is a request**, and the
authority is the command contract the request lands on, never the button that sent it.

See `UI-BINDING.md` for the adapter coverage table and the full attribute reference.

## 3. The Bridge

| Direction | API | Shape |
| --- | --- | --- |
| Core → UI | `Publish` / `Subscribe` / `Peek` | retained, so a late subscriber still gets the current value |
| UI → Core | `Dispatch` | fire and forget, never yields |
| UI → Core | `Invoke` | request/response, yields, contract must allow it |
| either | `Handle` | registers the handler on the realm that owns the command |

Retention is what makes adoption order irrelevant: an element tagged thirty seconds after
a value was published still renders the current state on its first frame.

Whether a dispatch stays local or crosses the wire is decided by the command's `Realm`,
not by the caller. The same line of client code works either way.

## 4. Security model

See `REMOTE-SECURITY.md` for the contract table and the ordered rejection paths. The
shape of it:

- **Deny by default.** No `AllowClient = true`, no client access.
- **The client's check is a convenience; the server's is the control.** The client refuses
  to send an illegal command so the mistake surfaces in development, and the server
  performs the identical check on arrival without caring what the client did.
- **Identity comes from the transport.** The player is the one Roblox puts in the remote
  callback's first argument, never a field in the payload.
- **Payloads are plain data, bounded.** Validated against `ArgumentSpec` — types, string
  lengths, numeric bounds and finiteness, table depth and entry counts. No Instances, no
  functions, no metatables, no cycles.
- **Two rate limits.** Per player per command, plus a global per-player budget so many
  cheap commands cannot evade the per-command budget.
- **One gateway.** A single RemoteEvent and a single RemoteFunction, both client→server.
  The server never invokes a client. Channel replication is a separate server→client event.
- **Channels declare how far they travel.** `Server` is the default, so a channel cannot
  leak by omission.
- **Refusals teach the client nothing.** The reason is logged server-side; the caller gets
  a coarse failure.

## 5. System lifecycle

1. `Init(unrest)` on every system, in dependency order.
2. `Start()` on every system, same order.
3. `Destroy()` in reverse order on shutdown.

The teardown hook is `Destroy`, not `Stop`, so it never collides with a domain verb:
`MusicSystem:Stop()` stops the music, `MusicSystem:Destroy()` retires the system.

Declaring `Dependencies` is how ordering is expressed. A system table must declare the
field even when empty (`{} :: { string }`) for the strict checker to match it structurally.

`PluginExtended` is the extension point: it registers third-party systems at runtime and
can load every ModuleScript in a folder, so a game adds capability without editing the
framework.

## 6. Type-checker notes when extending

Three patterns the strict checker forces:

- A system table must declare `Dependencies` even when empty, or it will not match
  `Types.System` structurally.
- State fields need an explicit type in the initial table literal: `_sound = nil :: Sound?`.
- A method must be defined before the method that calls it, because `self`'s type grows as
  the file is read.

## 7. File map

```
src/shared/            ReplicatedStorage.Unrest  — replicated, assume every client reads it
  init.luau            composition root; the singleton
  Primitives.luau      Signal/Maid/Connection types, zero requires
  Types.luau           the public type surface, re-exporting the two below
  Constants.luau       tag, attribute names, remote names, channels, commands, hard limits
  Util/                Signal, Maid, Resolver
  Core/init.luau       system registry and lifecycle
  Bridge/init.luau     publish/subscribe, dispatch/invoke, network routing
  Net/                 Types, Contracts, Client, Validate — public knowledge only
  Adapters/            registry, per-class adapters, selector, query engine
  Presets.luau         named attribute bundles a designer reaches for by name
  Elements/init.luau   adoption of tagged Studio UI (client-only at runtime)

src/server/            ServerScriptService.UnrestServer — never replicated
  init.server.luau     bootstrap
  Net/Server.luau      the authoritative gateway
  Systems/             MusicSystem, AvatarContext, DanceSystem, PluginExtended

src/client/            StarterPlayer.StarterPlayerScripts.UnrestClient
  init.client.luau     bootstrap: start, adopt tagged UI, bind queries
```
