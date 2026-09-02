# UnrestCoreSystem — Getting Started

Follow this once, in order, and you will have a screen that dispatches commands and follows
server state. You should not need to read any framework source to finish it.

Two facts explain everything below. **The framework builds no UI** — you build it in Studio
and tag it. **A command is unreachable from a client unless its contract says so** — and an
attribute is not a way around that.

Assumed: you know Roblox Studio. Not assumed: anything about this framework.

---

## 1. Get the framework into a place

```sh
rokit install          # once per clone; Rokit shims refuse to run otherwise
rojo serve             # serves default.project.json on port 34872
```

In Studio: **Plugins → Rojo → Connect**.

**You should see** three things appear in the Explorer:

| DataModel | From |
| --- | --- |
| `ReplicatedStorage.Unrest` | `src/shared` |
| `ServerScriptService.UnrestServer` | `src/server` |
| `StarterPlayer.StarterPlayerScripts.UnrestClient` | `src/client` |

**If you do not**, you are connected to a different project or serving from a different
directory — run `rojo serve` from the repository root, where `default.project.json` lives.

### Seed a worked example screen (optional, recommended)

`studio/BuildUnrestUI.luau` builds a demo screen so you have something real to look at. It is
**not** a Rojo mount and never becomes one — it is a one-off seed you run inside Studio.

* **Command bar:** paste the whole file in, press Enter.
* **Plugin:** drop the file in your Studio plugins folder for an **Unrest → Build UI** button.

**You should see** `[BuildUnrestUI] built StarterGui.UnrestDemo. 9 tagged elements, 11
attributes, ready for Play.` Everything it created is ordinary Studio instances that you now
own: rename, restyle, delete. Re-running rebuilds it as a single undo step. The framework only
ever reads the tag and the `Unrest*` attributes.

> UI never goes into the Rojo tree — no `.rbxmx` for a ScreenGui, no `StarterGui` mount, no
> `Instance.new("Frame")` in `src/`. If something seems to need UI in the repo, the answer is a
> tag and some attributes on an instance a designer already built.

---

## 2. Tag one element and press Play

The smallest possible win: one tag, no attributes, no code.

1. Insert a `ScreenGui` into `StarterGui` with a `TextButton` inside it (or use a seeded one).
2. **View → Tag Editor**, select the button, add the tag `Unrest`.
3. Press Play.

**You should see** one line per adopted element from the diagnostics module:

```
[UnrestClient] adopted game.Players.You.PlayerGui.Menu.Play
  [TextButton -> TextButton] role "Play": no wiring attributes -- adopted and queryable, nothing more
```

Read it left to right: the instance, its ClassName and the adapter that was resolved for it,
its **role** (the `UnrestRole` attribute, or `Instance.Name` when there is none), its group if
it has one, and then the attributes the framework *actually read* — which is the difference
between "my attribute is wrong" and "my tag is missing".

**If you see nothing**, after a few seconds you get
`[UnrestClient] no instance is tagged "Unrest", so the framework is managing nothing.` — the tag
is missing on the client's copy. Tag it in `StarterGui`, not in a running session's `PlayerGui`.

Tagging is live in both directions: add the tag while playing and you get an `adopted` line
immediately, remove it and you get a `released` line. Nothing restarts.

Diagnostics is opt-in. When you are done wiring a screen, delete this one line from
`src/client/init.client.luau` and nothing else changes:

```luau
require(script.Diagnostics)(unrest)
```

---

## 3. Make the button do something — with no code

Select the tagged `TextButton` and add two attributes in the Properties pane:

| Attribute | Type | Value |
| --- | --- | --- |
| `UnrestCommand` | string | `Music.Play` |
| `UnrestPayload` | string | `Lobby` |

Press Play. The adoption line now reads `UnrestCommand = Music.Play, UnrestPayload = Lobby`, and
clicking the button asks the server's `MusicSystem` to play the Lobby track.

That attribute is exactly equivalent to writing:

```luau
unrest:Dispatch("Music.Play", "Lobby")
```

**An attribute grants no privilege.** It goes through the same `Bridge:Dispatch` as
hand-written Luau; the contract in `Net/Contracts.luau` still decides what this client may
ask for, the server still validates the payload, and the server still applies the rate limit.
Type `Music.ForceStopAll` into `UnrestCommand` and it is refused with `NotClientCallable`,
because that contract never sets `AllowClient = true`. See
[REMOTE-SECURITY.md](REMOTE-SECURITY.md) for the command table.

Client-callable commands today: `Music.Play`, `Music.Stop`, `Music.SetVolume`, `Dance.Play`,
`Dance.Stop`. `UnrestCommand` only means something on a class that can be activated —
`TextButton`, `ImageButton`, `ClickDetector`, `ProximityPrompt`. On a `Frame` you get a warning
naming the element and the fix, and the rest of the screen keeps working.

Add `UnrestCooldown` (number, e.g. `0.25`) to stop a fat-fingered double click sending two
dispatches. It is a client-side debounce and **advisory only** — the real limit is the
per-player, per-command budget the server applies on arrival.

---

## 4. Make a label follow state — with no code

Insert a `TextLabel`, tag it `Unrest`, and add:

| Attribute | Type | Value |
| --- | --- | --- |
| `UnrestChannel` | string | `Music.NowPlaying` |
| `UnrestBind` | string | `Text` |
| `UnrestFormat` | string | `Now playing: {value}` |

Press Play. The label already shows the current track before you touch anything, because
channels are **retained**: the server published it at start-up and a late subscriber still gets
the last value. Click your button from step 3 and it follows. Adoption order
never matters — the label paints correctly whether the music started an hour ago or starts an
hour from now.

* `UnrestBind` can be omitted when the class has one obvious value: `TextLabel` writes `Text`,
  `ImageLabel` writes `Image`, `ScrollingFrame` writes `CanvasPosition`.
* Without `UnrestFormat` the value is written raw, which is how you drive a `Color3`, a `UDim2`
  or a `boolean` from a channel. With a format the result is always a string, and `nil` renders
  as empty rather than as the word `nil`.
* `UnrestBind` is an allowlist per class: `UnrestBind = "Parent"` warns rather than writing
  anything, because a value that can arrive from the server never sets an arbitrary property.

Channels available today: `Music.NowPlaying`, `Music.Volume`, `Dance.Current`,
`Avatar.Character`. (`Plugin.Registered` is server-only and never replicates.) The per-class
bindable property tables are in [UI-BINDING.md](UI-BINDING.md).

---

## 5. Collapse the repetition — `UnrestPreset` and `UnrestGroup`

Steps 3 and 4 do not scale: three attributes on every label, two on every button, plus a group
on each, is a lot of chances to typo `Music.NowPlaying`.

**A preset is a named bundle.** Replace the three attributes on your label with one:

| Attribute | Value |
| --- | --- |
| `UnrestPreset` | `NowPlayingLabel` |

Declared presets (`src/shared/Presets.luau`): `DanceButton`, `DanceStop`, `MusicStop`,
`MusicToggle`, `NowPlayingLabel`, `VolumeButton`.

A preset is a **default, never an override**, so the one thing that differs stays on the
element. Two volume buttons:

| Element | Attributes |
| --- | --- |
| `VolumeDown` | `UnrestPreset = VolumeButton`, `UnrestPayload = 0.2` |
| `VolumeUp` | `UnrestPreset = VolumeButton`, `UnrestPayload = 0.8` |

**A group is written once.** Set `UnrestGroup = "MainMenu"` on the **ScreenGui**. Every tagged
descendant inherits it, and `unrest:Query({ Group = "MainMenu" })` selects the lot.

The seed screen is the before-and-after. Nine elements:

| | Attributes |
| --- | --- |
| Before | **32** — command, payload, channel, bind, format and group retyped per element |
| After | **11** — one `UnrestGroup` on the ScreenGui, a preset name per element, and a payload where two buttons differ |

Two of the nine elements now carry no attributes at all: one is tagged purely so a group query
can count it, and one is bound from code (step 6).

Three rules govern this, and they are the whole model:

1. **Exactly three attributes are inherited** — `UnrestGroup`, `UnrestCooldown`, `UnrestPreset`.
   Inherit context, never intent: an inherited `UnrestCommand` would arm every descendant of a panel.
2. **Most specific wins** — the element's own attribute beats its preset, which beats the ancestor's.
3. **The walk stops at the first `LayerCollector`**, whose own attributes are read before it
   stops. A screen is the widest thing an inherited value is allowed to mean.

---

## 6. When to stop using attributes

`UnrestCommand` is *one fixed command*. The moment the right command depends on what is
currently true, you need code. That is what `Unrest:Query` is for:

```luau
unrest:Query({
    Tag = unrest.Tag,
    Selector = "GuiButton", -- is:A("GuiButton") -- TextButton and ImageButton both
    Role = "ToggleMenu",
}, {
    Active = function()
        local playing = unrest.Bridge:Peek("Music.NowPlaying")
        if playing == nil then
            unrest:Dispatch("Music.Play", "Lobby")
        else
            unrest:Dispatch("Music.Stop", nil)
        end
    end,
})
```

**`Role` falls back to `Instance.Name`.** A button simply named `ToggleMenu` matches that
query with no attribute written at all — and if a designer later renames it to
`Btn_04_final`, they set `UnrestRole = "ToggleMenu"` and it keeps matching. Naming an element
well is usually cheaper than writing an attribute; prefer `Role` over `Name` in a descriptor
for exactly that reason.

The query is a **live binding**, not a scan: create it before the element exists and an element
tagged ten minutes from now is bound ten minutes from now. Its lifetime is yours — call
`:Destroy()` on the handle when the screen it serves goes away.

Handler names, the same for every class: `Active`, `Secondary`, `Press`, `Release`, `Hover`,
`Unhover`, `Focus`, `Blur`, `Submit`, `Changed`, `Added`, `Removed`. Which ones a given class
supports is in [UI-BINDING.md](UI-BINDING.md).

> **Code raises; attributes warn.** Binding `Submit` from code to a `TextLabel` throws — it is
> a bug in code you wrote. The same mistake typed into an attribute only warns, because it is
> data typed by somebody who is not watching the Output window, and taking the screen down
> would be worse.

---

## 7. Add a command of your own

Five edits, in this order. The first grants nothing on its own; the second is the one that
decides what a client may ask for.

**1. Name it once**, in `src/shared/Constants.luau` — `Commands.ShopBuy = "Shop.Buy"` and
`Channels.ShopBalance = "Shop.Balance"`. Names live here so they are never spelled twice.

**2. Declare the contract** in `src/shared/Net/Contracts.luau`. Leaving `AllowClient` out means
no client can reach it, and that absence *is* the denial:

```luau
[Constants.Commands.ShopBuy] = {
    Name = Constants.Commands.ShopBuy,
    Realm = "Server",
    AllowClient = true,
    Payload = IDENTIFIER,
    RateLimit = { Count = 2, Window = 1 },
    Response = true,
    Description = "Buy a catalogue item by name.",
},
```

**3. Declare the channel** you will publish results on, in the same file. `Visibility` defaults
to `Server`, so a channel a client should see has to say so:

```luau
[Constants.Channels.ShopBalance] = {
    Name = Constants.Channels.ShopBalance,
    Visibility = "Player",
    Value = { Kind = "number", Min = 0 },
    Description = "The receiving player's balance.",
},
```

**4. Handle it** in a server system's `Init`, and publish the result:

```luau
function ShopSystem:Init(unrest: Types.Unrest): ()
    local bridge = unrest.Bridge

    self._maid:Add(bridge:Handle(Constants.Commands.ShopBuy, function(source: Types.CommandSource, payload: any): boolean
        local player = source.Player
        if player == nil then
            return false -- a local server dispatch has no caller
        end

        local bought = self:Buy(player, payload :: string)
        bridge:Publish(Constants.Channels.ShopBalance, self:BalanceOf(player), player)
        return bought
    end))
end
```

`payload` needs no type check — the gateway already proved it against the contract's schema —
and the caller is `source.Player`, straight from the transport, never a field in the payload.
Register the system with `Unrest:Register(ShopSystem)` in `src/server/init.server.luau`, and
declare `Dependencies = {} :: { string }` on the system table even when it is empty.

**5. Point the UI at it.** `UnrestCommand = "Shop.Buy"` and `UnrestPayload = "Sword"` on a
button; `UnrestChannel = "Shop.Balance"` and `UnrestFormat = "Coins: {value}"` on a label. No
new client code — and if you write the same attributes twice, add a preset.

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `no instance is tagged "Unrest"` after a few seconds | Nothing carries the tag on the client's copy | Tag the instance in `StarterGui` via **View → Tag Editor**. Tagging a `ScreenGui` does **not** adopt its children — each element you want managed is tagged itself |
| Adopted, but the adoption line shows `no wiring attributes` | The attribute is misspelled, or it is on the wrong instance | Attribute names are case-sensitive and start with `Unrest`. `UnrestCommand`, `UnrestPayload`, `UnrestChannel`, `UnrestBind`, `UnrestFormat` and `UnrestRole` are **never inherited** — they must be on the element itself |
| `"Music.ForceStopAll" refused (NotClientCallable)` | The contract does not set `AllowClient = true` | Use a client-callable command, or add the line in `Net/Contracts.luau` if a client genuinely should be able to ask. The mistake is the same whether it came from an attribute or from code |
| Binding `Changed` from code throws | The class has no single value property — a `Frame` has none | Bind `Changed` to a class that has one (`TextLabel`, `TextButton`, `TextBox`, `ImageLabel`, `ScrollingFrame`, `UICorner`, `UIScale`), or drop the handler. The error names the class and lists what it does support |
| `... is not a declared preset` | `UnrestPreset` is misspelled | The warning lists every declared preset. Fix the spelling, or add it with `Presets.Register(name, bundle)`. The element is still adopted, with its own attributes only |
| `Query({ Group = ... })` matches nothing | Nothing on the chain sets `UnrestGroup`, the walk hits a `LayerCollector` before reaching it, or the elements are not tagged | Set `UnrestGroup` on the `ScreenGui` the elements actually live under, and tag each element. Inheriting a group does not adopt an untagged instance |
| `sets UnrestBind = "X", which is not bindable` | The property is not on that class's allowlist | Use a property from the class's bindable table in [UI-BINDING.md](UI-BINDING.md), or register an adapter that permits it |
| `sets UnrestChannel but there is nothing to write it into` | The class has no default value property | Add `UnrestBind = "<property>"` |
| Label stays blank | The channel published `nil` and there is no format | Add `UnrestFormat` — no Roblox property accepts `nil`, so without a format there is nothing to write |
| An attribute change does nothing | You changed it on an untagged or released instance | Changing an attribute on a managed element re-wires it live; changing an inheritable one on an ancestor re-wires every managed descendant. Neither needs a restart |

---

## Where to go next

* [UI-BINDING.md](UI-BINDING.md) — full attribute reference, every handler, and the per-class
  table of supported events and bindable properties.
* [REMOTE-SECURITY.md](REMOTE-SECURITY.md) — the contract table, the ordered rejection paths, and
  what a payload may contain.
* [ARCHITECTURE.md](ARCHITECTURE.md) — the layer contract, the Bridge, and the system lifecycle.
