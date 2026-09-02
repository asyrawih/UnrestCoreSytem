# UnrestCoreSystem — Remote Security

> The Bridge is the framework's controller *and* its client/server boundary. This document is
> the boundary half: what a client can reach, what it cannot, and why the "cannot" is a
> property of the design rather than a check somebody remembered to write.

---

## 1. The one idea

**A command is unreachable from a client unless its contract says otherwise, and the server
decides that by reading the contract, never by reading the message.**

Every mechanism below is a consequence. The important half is the second clause: because the
permission is looked up by *name* in a table the server owns, nothing a client sends can widen
its own permissions — the permission was never in the message, and the envelope has nowhere to
put one.

```
    CLIENT                                   |  SERVER
                                             |
  Bridge:Dispatch("Music.Play", "Lobby")     |
        |                                    |
        | contract.Realm == "Server"         |
        v                                    |
  Net/Client.luau  -- advisory guard --------|-----------------------------.
        |          (a convenience, not a control)                          |
        | FireServer(command, payload)       |                             |
        `------------------------------------|--> Net/Server.luau          |
                                             |     1 UnknownCommand        |
                                             |     2 NotClientCallable  <--' same test,
                                             |     3 WrongRealm            this one counts
                                             |     4 ResponseNotAllowed
                                             |     5 RateLimited (global)
                                             |     6 RateLimited (command)
                                             |     7 BadPayload
                                             |     8 Unauthorized
                                             |          |
                                             |          v
                                             |     Bridge:Execute -> handler (pcall)
                                             |          |
                                             |          v
                                             |     Bridge:Publish -> channel visibility
                                             |          |
    Bridge:Subscribe  <----- UnrestPublish --|----------'
```

---

## 2. Where the files live, and why that is a security property

| File | Realm | Why there |
| --- | --- | --- |
| `src/shared/Net/Types.luau` | ReplicatedStorage | Types only. |
| `src/shared/Net/Contracts.luau` | ReplicatedStorage | **Public knowledge on purpose.** A list of door names and which have an outside handle. |
| `src/shared/Net/Validate.luau` | ReplicatedStorage | Same schema walker both sides; it holds no policy. |
| `src/shared/Net/init.luau` | ReplicatedStorage | Locates/creates the three remotes. The envelope shape. |
| `src/shared/Net/Client.luau` | ReplicatedStorage | The Bridge must construct it on the client. |
| `src/server/Net/Server.luau` | **ServerScriptService** | **The policy is never replicated to the machines it polices.** |

A client can read the contract table. That is not a leak: knowing that `Music.ForceStopAll`
exists and is server-only tells an attacker nothing they can act on, because the lock is in
`src/server/Net/Server.luau`, which they never receive.

The asymmetry in how the two gateways are attached follows from this. The client half is built
by the Bridge's own constructor — so a client is networked *by construction* and a bootstrap
cannot fail open by forgetting to wire it. The server half cannot be reached from
ReplicatedStorage at all, so the server bootstrap attaches it explicitly through
`NetTypes.BridgeSeam.AttachGateway`.

---

## 3. The contract table

### Commands

| Command | Realm | Client-callable | Payload schema | Rate limit | Authorize | Response |
| --- | --- | --- | --- | --- | --- | --- |
| `Music.Play` | Server | **yes** | `string`, ≤64, `[%w_%-%.]+` | 4 / 1s | — | yes |
| `Music.Stop` | Server | **yes** | *none* → `nil` only | 4 / 1s | — | no |
| `Music.SetVolume` | Server | **yes** | `number`, 0…1 | 8 / 1s | — | no |
| `Music.ForceStopAll` | Server | **no** | *none* → `nil` only | 10 / 1s (default) | — | no |
| `Dance.Play` | Server | **yes** | `string`, ≤64, `[%w_%-%.]+` | 3 / 2s | living character | yes |
| `Dance.Stop` | Server | **yes** | *none* → `nil` only | 3 / 2s | — | no |
| `Plugin.Reload` | Server | **no** | *none* → `nil` only | 10 / 1s (default) | — | yes |

Plus a **global budget of 60 requests per second per player**, across every command combined.

The two server-only rows are worked examples, and what makes them examples is what is *not*
written in them. There is no `Private = true`, no `Admin` flag, no guard clause. They are
unreachable because nobody wrote `AllowClient = true`. Adding a name to `Constants.Commands`
grants nothing; only a row in `Net/Contracts.luau` with that line does.

`Music.SetVolume` deserves a note: volume is shared state, so one player's slider is heard by
everyone. It is client-callable because the framework's demo needs a command that writes global
state through the gate, and it is rate limited hard for that reason. A shipping game adds an
`Authorize` there — see `Dance.Play` for the shape — and the point of the table is that doing
so is a one-line change in one file, with no handler, UI, or transport code to touch.

### Channels

| Channel | Visibility | Value schema | Note |
| --- | --- | --- | --- |
| `Music.NowPlaying` | Public | `string?`, ≤64 | Shared by definition. |
| `Music.Volume` | Public | `number`, 0…1 | Shared by definition. |
| `Dance.Current` | Player | `string?`, ≤64 | Addressed to its owner. |
| `Avatar.Character` | Player | `string?`, ≤64 | The character's **name**, never the Model. |
| `Plugin.Registered` | **Server** | — | Declared with **no `Visibility` line at all.** |

`Plugin.Registered` is the channel-side worked example: the safe answer is the one you get by
not thinking about it. `Server` is the default, so a channel someone forgets to declare, or
declares carelessly, does not replicate.

`Avatar.Character` is the second one. `AvatarContext` holds the live character `Model` on the
server, where a handle into the data model belongs, and publishes only the name. That is
enforced twice: by the channel's `string?` schema, and — if the schema were removed — by the
plain-data whitelist, which refuses any `Instance`. Flipping this channel to `Public` by
accident produces a refusal in the server log, not a leak.

---

## 4. Rejection paths, in order

`Net/Server.luau` refuses a request at the first line that says no. The order is not arbitrary.

| # | `RejectionReason` | Trigger |
| --- | --- | --- |
| 1 | `UnknownCommand` | The envelope's first field is not a 1…128-character string, or no contract declares it. |
| 2 | `NotClientCallable` | The contract does not set `AllowClient = true`. **This is the security control.** |
| 3 | `WrongRealm` | The contract does not run this command on the server. |
| 4 | `ResponseNotAllowed` | `Invoke` was used on a command with no `Response = true`. |
| 5 | `RateLimited` | The player's **global** budget across all commands is spent. |
| 6 | `RateLimited` | The player's budget for **this** command is spent. |
| 7 | `BadPayload` | The payload does not satisfy the contract's `ArgumentSpec`. |
| 8 | `Unauthorized` | The contract's `Authorize` hook said no — or threw, which also fails closed. |
| 9 | `HandlerError` / `NoHandler` | The handler threw, or nothing is registered. Not the client's fault; not counted against them. |

Three of those orderings are load-bearing:

* **The client-callable test is second, before anything reads the payload.** A command a client
  may not call is refused without its arguments ever being examined, so an unreachable
  command's schema is not an attack surface.
* **Rate limiting comes before schema validation.** Walking a deep table is the expensive part
  of a request, and that expense should fall on the flood's own budget rather than on the
  server's frame time.
* **The global budget is checked before the per-command one.** Per-command limits alone can be
  evaded by spreading a flood across many different cheap commands, each individually under its
  own ceiling. The global bucket is what makes the sum bounded too.

### What the caller learns

The coarse `Reason`, and nothing else. Every `Detail` — the failing field, the `Authorize`
hook's reason, a handler's traceback — is logged on the server and never crosses the wire. A
client probing `Dance.Play` cannot tell "you are dead" from "you are not loaded" from "that
emote is staff-only", so it cannot map the inside of the server by watching which lies fail
differently.

### The client's own refusals

`Net/Client.luau` runs the *identical* test before sending and fires `NetClient.Refused` when it
fails. That refusal buys exactly two things: a loud signal at the keyboard when a programmer
dispatches something the contract never opened, and no wasted remote traffic. It buys **zero**
security — it runs on a machine the player owns and an exploiter simply deletes it. The server
does not know, ask, or care whether it ran. If the two ever disagree, the server wins; if you
have to delete one, delete the client's.

---

## 5. Payload validation

`Net/Validate.luau` is a **whitelist**. A value is refused unless it is one of:

```
nil   boolean   number   string   table   Vector3   Color3   EnumItem
```

Everything else is refused without being inspected — `Instance`, function, thread, userdata, a
table with a metatable, a table that points at itself. Each of those is a specific hazard rather
than a stylistic objection: an `Instance` is a live reference a handler might write through; a
metatable turns `payload.Anything` into attacker-chosen code; a cyclic table turns any recursive
walk into a hang.

Everything is also bounded, because the cost of checking is itself an attack surface
(`Constants.Limits`):

| Limit | Value | Bounds |
| --- | --- | --- |
| `MaxPayloadDepth` | 4 | Nesting, so the walk cannot be made deep. |
| `MaxPayloadEntries` | 32 | Entries per table, so it cannot be made wide. |
| `MaxStringLength` | 256 | Every string, including table keys. A contract's `MaxLength` can only be stricter. |

On top of the kind check, an `ArgumentSpec` may require: `Optional`, `MaxLength`, a `Pattern`
that must match **in full**, numeric `Min`/`Max` (non-finite numbers — `NaN` and both
infinities — are rejected before bounds are considered, because they sail through a naive
comparison), `OneOf`, and recursive `Of` / `Fields`.

Two rules there are deny-by-default restated one level down:

* A command with **no** `Payload` accepts `nil` and nothing else. A handler written against
  `nil` can never be surprised by a table.
* A schema with `Fields` **rejects undeclared fields** rather than ignoring them. An undeclared
  field is not free space.

Handler *return* values crossing back to a client get the same plain-data whitelist, so a
handler cannot casually hand an `Instance` to a caller who asked for a boolean.

---

## 6. Identity

The player is **the first argument Roblox puts in the remote callback**, and nothing else is
ever consulted:

```luau
created.Dispatch.OnServerEvent:Connect(function(player: Player, command: any, payload: any)
    handle(player, command, payload, false)
end)
```

It reaches a handler as `CommandSource.Player`. There is no `payload.Target`, no `payload.UserId`,
no `payload.IsAdmin` — and, crucially, nowhere in the envelope to put one. "Play an emote on
someone else's character" is not a request this framework validates carefully; it is a request it
cannot represent. `CommandSource.Remote` tells a handler whether the request crossed the wire at
all; handlers that mutate authoritative state branch on that, never on the payload.

---

## 7. Rate limiting

A **token bucket** per player per command, plus one global bucket per player.

The choice over a sliding window of timestamps is itself a security property: a timestamp list
grows with the flood that fills it, so rate-limiting an attacker would cost more the harder they
attacked. A token bucket is two numbers, O(1) in time and space no matter what arrives.

A player's buckets and rejection counter are deleted on `PlayerRemoving`, so the state table
cannot grow for the life of the server — a join/leave loop is not a memory leak.

---

## 8. Abuse reporting, not vigilantism

Rejections are counted per player. Past `Constants.Limits.AbuseThreshold` (25), and every 25
after that, `NetServer.AbuseDetected` fires with the player and the count. The framework then
does nothing.

Kicking on a heuristic bans the player with the bad connection and the one whose button
double-fired. The framework does not know what a cheater is in your game; the signal is the seam
where your moderation plugs in. `NetServer.Rejected` is the matching seam for telemetry.

A `HandlerError` is explicitly *not* counted against the player. A crashing system must not be
able to get its own users reported.

---

## 9. Transport shape

Three replicated objects, and there are never more:

| Object | Direction | Purpose |
| --- | --- | --- |
| `UnrestDispatch` (RemoteEvent) | client → server | Fire and forget. |
| `UnrestInvoke` (RemoteFunction) | client → server | Request/response. |
| `UnrestPublish` (RemoteEvent) | server → client | Channel replication. |

One choke point per direction, not a remote per feature: there is exactly one function in the
codebase that decides whether a request lives, so a new feature adds a row to a table rather than
a door.

**The server never invokes a client.** `RemoteFunction:InvokeClient` hands a server thread to a
machine the server does not control, with no timeout available to break it; a client that simply
never returns stalls that thread forever. Server → client traffic is one-way `FireClient`.

Correspondingly, the server never *commands* a client either — `Bridge:Dispatch` of a
`Realm = "Client"` command from the server is a `WrongRealm` rejection, by design. The server
cannot verify that a client complied, so a command pointed that way would be a suggestion dressed
as a mechanism. Server → client is state on a channel, and the client decides what to render.

The client's `Invoke` bounds itself with `Constants.Limits.InvokeTimeout` (10s) by racing the
call against a `task.delay`, because `InvokeServer` has no timeout of its own. It never retries:
an automatic retry on a timeout is how a struggling server gets a second copy of every request it
is already late on.

The remotes are created **at the end** of the server bootstrap. That is the whole reason
`gateway:Start()` is the last line: the door becomes reachable only once every handler is
registered, so there is no window in which it is open and the room behind it is empty.

---

## 10. Handler isolation

Handlers run under `xpcall` inside `Bridge:Execute`. One bad system cannot stall the gateway for
every other player. The traceback is captured and logged **on the server**, where it is useful;
the caller receives `HandlerError` and nothing more.

`Bridge:Execute` is deliberately gate-free — no validation, no rate limiting, no authorization —
and it is deliberately **not** on `Types.Bridge`. It lives on `NetTypes.BridgeSeam`, which the
server gateway casts to, so the only thing in the codebase that can reach an unchecked handler is
the object that just finished checking.

---

## 11. Threat model — what this does and does not stop

**Stopped:**

- Calling a server-only command from a client, however the client is patched.
- Forging identity: there is no field for it.
- Sending a malformed, oversized, deeply nested, cyclic, or `Instance`-bearing payload.
- Flooding one command, or many cheap commands, or joining and leaving to reset budgets.
- Learning why a request failed beyond a coarse reason.
- Leaking a `Server` channel by forgetting to think about it.
- A crashing handler taking down the gateway or getting its own players reported.

**Not stopped, and out of scope:**

- A client lying about *legitimate* input within its schema — `Dance.Play("Wave")` when the
  player would rather not. Only an `Authorize` hook, which can see game state, can judge that.
- Application-level logic errors inside a handler. The gate proves the shape, not the meaning.
- Traffic analysis: contract names are public, so an attacker knows what exists. That is by
  design; the locks are not in the same building as the map.
