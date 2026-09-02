# UnrestCoreSystem — UI Binding

> The framework builds no UI. It manages UI you already built.

There is no `Mount`, no component library, and no code path anywhere in Unrest that
constructs a `GuiObject`. Every element the framework touches was made by hand in Roblox
Studio. What Unrest supplies is the other half: it learns what your instance *is*, wires it
to framework state, and keeps that wiring alive while the instance comes and goes.

---

## 1. The opt-in is one tag

```
CollectionService tag:  Unrest
```

Tag an instance and, from that moment:

1. an **adapter** is resolved for its ClassName, so the framework knows which events it has
   and which properties may be written into it;
2. its `Unrest*` **attributes** are read and wired — including a command it dispatches and a
   channel it follows, with no code at all;
3. it becomes visible to **`Unrest:Query`**.

Remove the tag (or destroy the instance) and all of that is released, in one step, with
nothing left connected.

Tagging is live in both directions. A query created before its element exists binds the
element the instant it is tagged; an element tagged during a play session is adopted during
that session. Nothing needs restarting and no script needs re-running.

```luau
-- In Studio: View > Tag Editor > add "Unrest" to the instance.
-- Or, from code:
game:GetService("CollectionService"):AddTag(button, "Unrest")
```

Adoption is **client-only**. A tagged ScreenGui exists on the server too, but binding its
events there would be misleading: a UI event is a *request*, and the authority is the
command contract the request lands on — never the button.

### The tag cascades

Tagging an instance manages that instance **and every `GuiObject` under it**. A screen is
opted in by tagging its container once, not by tagging forty buttons:

```
ScreenGui  ← tag "Unrest" here, once
└── Frame                     managed
    ├── UIListLayout          not managed — see below
    ├── TextButton "Play"     managed
    ├── TextButton "Stop"     managed
    └── TextLabel  "Now"      managed
```

Tag a single button and you still get a single button, because a button rarely has
GuiObject children. It is one rule and it reads correctly both ways.

Everything else in this document is unchanged by that. A cascaded element is an element:
it resolves an adapter, it reads its own `Unrest*` attributes, it inherits the ones that
are inheritable, and `Unrest:Query({ Tag = "Unrest", ... })` finds it. There is no second
class of adoption.

**Only `GuiObject` descendants are swept up.** A `UIListLayout`, `UIPadding`, `UICorner` or
`UIStroke` under a tagged Frame is left alone. They carry no events and exist to lay other
things out, so adopting them would be noise in `All()` and in every query. Tagging one
yourself still adopts it — that is how you bind a channel to a `UIStroke.Color`, and it
keeps working exactly as before.

### `UnrestIgnore` — the way back out

| | |
| --- | --- |
| `UnrestIgnore` | `true` |

Set it on any instance and the cascade stops there: that instance and everything under it
are released, and nothing under it is adopted. It is the escape hatch for the one
decorative subtree inside an otherwise managed screen.

```
ScreenGui  ← tag "Unrest"
├── Buttons              managed
│   └── TextButton       managed
└── Decor                UnrestIgnore = true → released
    ├── ImageLabel       not managed
    └── Frame            not managed
```

It is **live in both directions**. Ticking the checkbox in Studio while the game runs
releases the subtree; clearing it adopts the subtree back. Nothing restarts.

Three details worth knowing:

* It must be the **boolean** `true`. The one attribute that removes elements from the
  framework is not the one attribute that guesses at `"true"` typed into a string.
* **A tag beats it.** `UnrestIgnore` opts a subtree out of a *cascade*, so tagging one
  instance inside an ignored subtree adopts that instance anyway — including a `UIStroke`
  you want a channel bound to.
* An instance that is both tagged **and** ignored manages itself and stops the cascade
  below it. Both attributes still mean exactly what they say.

### What is live, and what it costs

| Edit | Result |
| --- | --- |
| tag a container | it and every GuiObject under it are adopted, immediately |
| untag it | they are released — unless a second tagged ancestor, or their own tag, still covers them |
| parent a GuiObject into a managed subtree | adopted on arrival |
| parent one out | released, unless something still covers it where it landed |
| set `UnrestIgnore` | that subtree is released |
| clear `UnrestIgnore` | that subtree is adopted back |

Nested tags do not fight. An element covered by two tagged ancestors stays managed until
both are gone, because coverage is **re-derived** on every change rather than counted:
whatever happened, the framework asks `Selector.isManaged` again. There is no reference
count to decrement in the wrong order.

The connection budget is deliberately shallow — one `DescendantAdded` per tagged **root**,
never one per descendant. Departures are not watched on the root at all: every adopted
element already watches its own `AncestryChanged`, which fires *after* a move with the
final parent in place, so the question it re-asks has a true answer. The only other
watches are one `UnrestIgnore` per adopted element (which already carries a maid) and one
per *gate* — an instance carrying `UnrestIgnore`, or a Folder the cascade descends through.
There is a handful of those in a screen rather than one per `UICorner`.

---

## 2. Attribute reference

Every attribute is optional. An instance with only the tag is still adopted and still
queryable; it simply does nothing on its own.

| Attribute | Type | Meaning |
| --- | --- | --- |
| `UnrestRole` | string | Logical name used by `Descriptor.Role`. Falls back to `Instance.Name`. |
| `UnrestGroup` | string | Free-form grouping (`"MainMenu"`, `"Shop"`), selected by `Descriptor.Group`. |
| `UnrestCommand` | string | Command dispatched through `Bridge:Dispatch` when the element is activated. |
| `UnrestPayload` | any attribute value | Payload sent with `UnrestCommand`. |
| `UnrestChannel` | string | Channel subscribed to for the element's displayed value. |
| `UnrestBind` | string | Property the channel value is written into. Defaults to the adapter's `ValueProperty`. |
| `UnrestFormat` | string | Template applied to the channel value. `{value}` is the hole. |
| `UnrestCooldown` | number | Client-side debounce, in seconds, between activations. **Advisory only.** |
| `UnrestPreset` | string | Names a bundle in `Presets.luau` that expands into several of the attributes above. |
| `UnrestIgnore` | boolean | `true` opts this instance and its whole subtree back out of a cascading tag. Structural, not wiring: it never joins the merge below. |

Changing one on the element re-wires **that element only**, live, through
`GetAttributeChangedSignal`. Editing `UnrestFormat` in Studio while the game runs repaints
the label on the next publish; you do not restart anything. Changing an *inheritable*
attribute on an ancestor re-wires every managed descendant, and moving an element re-resolves
it against its new ancestors — also live, also without a restart.

### A button, with zero code

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestCommand` | `Music.Play` |
| `UnrestPayload` | `Lobby` |

Activating it calls `Bridge:Dispatch("Music.Play", "Lobby")`.

### A label that follows framework state, with zero code

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestChannel` | `Music.NowPlaying` |
| `UnrestBind` | `Text` |
| `UnrestFormat` | `Music: {value}` |

Channels are **retained**, so the label paints itself correctly the moment it is adopted,
whether the music started an hour ago or starts an hour from now. Order stops mattering.

`UnrestBind` may be omitted when the class has an obvious value: a `TextLabel` writes
`Text`, an `ImageLabel` writes `Image`, a `ScrollingFrame` writes `CanvasPosition`. That
default is the adapter's `ValueProperty` (see §5).

With no `UnrestFormat`, the published value is written raw — which is how you drive a
`Color3`, a `UDim2` or a `boolean` from a channel. With a format, the result is always a
string, and a `nil` value renders as empty rather than as the word `nil`.

### Resolution: three layers, most specific wins

`UnrestGroup = "MainMenu"` repeated on nine buttons is nine chances to typo it. Two features
remove that repetition without moving any decision out of Studio, and `element.Attributes` is
the merge of all three layers, weakest first:

| Layer | Where it comes from | Beats |
| --- | --- | --- |
| 3. inheritance | the nearest ancestor that sets one of the inheritable attributes | nothing |
| 2. the preset | the bundle `UnrestPreset` names, from `Presets.luau` | inheritance |
| 1. the element | what you set on this instance | both |

So **a preset is a default, never an override**, and an ancestor is a fallback, never a
mandate. Setting `UnrestPayload` on one button that uses the `MusicToggle` preset changes that
button and nothing else.

`ManagedElement.Sources` records which layer won each key, so "who set this?" has an answer
without opening three property panels:

```luau
local element = unrest.Elements:Get(button)
print(element.Preset)                                --> MusicToggle
print(element.Sources.UnrestCommand.Origin)          --> Preset
print(element.Sources.UnrestGroup.Text)              --> inherited from Menu (ScreenGui)
print(require(Unrest.Elements).describe(element))
--> UnrestChannel = Music.NowPlaying (from preset "MusicToggle"),
--> UnrestGroup = MainMenu (inherited from Menu (ScreenGui)),
--> UnrestPayload = Dancefloor (set here)
```

### `UnrestPreset` — the bundle

```luau
-- src/shared/Presets.luau
MusicToggle = {
    UnrestCommand = "Music.Play",
    UnrestPayload = "Lobby",
    UnrestChannel = "Music.NowPlaying",
    UnrestBind    = "Text",
    UnrestFormat  = "Music: {value}",
}
```

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestPreset` | `MusicToggle` |

One attribute instead of five. The point is not brevity: it is that *what a music toggle is*
gets decided once, in code, under review, instead of being retyped on every button and
drifting. `Presets.Register(name, bundle)` adds one at runtime; `Presets.List()` names them
all.

A preset is a shorthand and not a privilege. A preset naming a command the contracts do not
declare is refused at dispatch exactly as a hand-typed `UnrestCommand` would be.

Naming a preset that does not exist warns and adopts the element anyway, with its own
attributes only:

```
[Unrest.Elements] game.Players.You.PlayerGui.Menu.Play resolves UnrestPreset = "MusicTogle"
(set here), which is not a declared preset. Declared presets: DanceButton, DanceStop,
MusicStop, MusicToggle, NowPlayingLabel, VolumeButton. The element was adopted with its own
attributes only -- fix the spelling, or declare it with Presets.Register("MusicTogle", ...).
```

### Inheritance — context, never intent

Exactly three attributes are inherited from an ancestor, and they are listed in
`Constants.Inheritable`:

| Attribute | Why it is inheritable |
| --- | --- |
| `UnrestGroup` | which screen an element is on — every element on that screen shares the answer |
| `UnrestCooldown` | a house debounce for a panel of buttons |
| `UnrestPreset` | a default bundle for everything under one container |

Everything else — `UnrestRole`, `UnrestCommand`, `UnrestPayload`, `UnrestChannel`,
`UnrestBind`, `UnrestFormat` — is **per-element intent and is never inherited**. Inheriting a
command would silently arm every descendant of a panel with the same command, which is the
opposite of a feature. `UnrestRole` is this element's identity, so it stays put too.

The walk goes up from the element's parent and stops at the **first `LayerCollector`**
(`ScreenGui`, `SurfaceGui`, `BillboardGui`), whose own attributes are read before stopping. A
screen is the widest thing an inheritable attribute is allowed to mean. Services and the
DataModel are never read at all — `UnrestGroup` on `Players` would be a global, and a global
is what this is not.

Every ancestor on that chain is watched, not only the ones supplying a value today: a nearer
ancestor that sets `UnrestGroup` tomorrow has to win the moment it does. The connections hang
off the element's own maid and are torn down and rebuilt on every re-resolution, so a
reparented element holds connections to its new ancestors only.

> **The cascade multiplies inheritance.** `UnrestGroup` on a ScreenGui now reaches every
> GuiObject under it rather than only the ones you tagged, which is the point. `UnrestPreset`
> reaches them too, and a preset carrying `UnrestCommand` would arm the lot — so put a preset
> that expands into a command on the elements that have that intent, and keep the ancestor for
> the ones that are genuinely house style. You will hear about it either way: a preset that
> arms a `TextLabel` warns that `Active` cannot bind to it, naming the element.

> **Queries see inherited groups.** `Descriptor.Group` goes through `Selector.groupOf`, which
> reads the element, then its preset, then walks the same ancestor chain. So `UnrestGroup`
> written once on a ScreenGui is enough for `Unrest:Query({ Group = "MainMenu" })` to select
> everything under it. `Selector.ancestorChain` is the single definition of that walk --
> `Elements` resolves with it and `Query` watches the chain it returns, so the two cannot
> disagree about which ancestors count.
>
> The cascade is defined the same way and for the same reason: `Selector.isManaged` answers
> "is this managed?", `Selector.cascadeUnder` answers "what is managed under here?", and both
> `Elements` and `Query` are callers rather than second opinions.
>
> One difference between the two walks is deliberate. The inheritance walk stops at the first
> `LayerCollector`; the cascade walk does not. A group that leaked past a ScreenGui would
> start selecting elements on unrelated screens, because it is ambient context — whereas a tag
> was put on one specific container on purpose, and tagging a Folder of ScreenGuis is a thing
> somebody may well have meant. Neither walk reads a service or the DataModel.

### An attribute grants no privilege

`UnrestCommand` goes through the **exact same `Bridge:Dispatch`** as hand-written Luau. The
command's contract still decides whether a client may ask for it at all, the server still
validates the payload, and the server still applies the rate limit. Adding an attribute in
Studio cannot widen what this client is allowed to request, because the permission was never
in the attribute.

`UnrestCooldown` is a **client-side debounce and nothing more**. It exists so a fat-fingered
double click does not send two dispatches. It lives in this client's memory, anybody who
cares to remove it can, and it is not a rate limit. The real limit is the per-player,
per-command budget the server applies on arrival.

---

## 3. The handler vocabulary

Handlers are the same ten verbs whatever the class underneath is, plus two that describe the
query rather than the element. Every handler is called as `(element, value)`, and `value` is
nil for all but two of them — a one-parameter `function(element) end` is the normal shape.

### Where each handler comes from

Adapters compose along the class hierarchy, so a handler declared on `GuiObject` belongs to
**every** GuiObject, and one declared on `GuiButton` belongs to both button classes. A handler
appearing on more than one row is a *different Roblox event per family*, deliberately given
one name so a single query can select "everything activatable in this room".

| Handler | Declared on | Roblox event | Reaches | `value` |
| --- | --- | --- | --- | --- |
| `Active` | `GuiButton` | `Activated` | `TextButton`, `ImageButton` | nil |
| `Active` | `ClickDetector` | `MouseClick` | `ClickDetector` | nil — the Player is dropped |
| `Active` | `ProximityPrompt` | `Triggered` | `ProximityPrompt` | nil — the Player is dropped |
| `Secondary` | `GuiButton` | `MouseButton2Click` | `TextButton`, `ImageButton` | nil |
| `Secondary` | `ClickDetector` | `RightMouseClick` | `ClickDetector` | nil |
| `Press` | `GuiObject` | `InputBegan`, filtered to MouseButton1 / Touch | every GuiObject | nil |
| `Press` | `ProximityPrompt` | `PromptButtonHoldBegan` | `ProximityPrompt` | nil |
| `Release` | `GuiObject` | `InputEnded`, same filter | every GuiObject | nil |
| `Release` | `ProximityPrompt` | `PromptButtonHoldEnded` | `ProximityPrompt` | nil |
| `Hover` | `GuiObject` | `MouseEnter` | every GuiObject | nil |
| `Hover` | `ClickDetector` | `MouseHoverEnter` | `ClickDetector` | nil — the Player is dropped |
| `Hover` | `ProximityPrompt` | `PromptShown` | `ProximityPrompt` | nil — the input type is dropped |
| `Unhover` | `GuiObject` | `MouseLeave` | every GuiObject | nil |
| `Unhover` | `ClickDetector` | `MouseHoverLeave` | `ClickDetector` | nil |
| `Unhover` | `ProximityPrompt` | `PromptHidden` | `ProximityPrompt` | nil |
| `Focus` | `TextBox` | `Focused` | `TextBox` only | nil |
| `Blur` | `TextBox` | `FocusLost` | `TextBox` only | nil |
| `Submit` | `TextBox` | `FocusLost` **with Enter pressed** | `TextBox` only | the committed `Text`, a string |
| `Changed` | *synthesised from `ValueProperty`* | `GetPropertyChangedSignal(ValueProperty)` | every class with a `ValueProperty` | that property's current value |
| `Added` | *query lifecycle* | — | every instance, adapter or not | nil |
| `Removed` | *query lifecycle* | — | every instance, adapter or not | nil |

Whatever argument the Roblox event carried is **not** forwarded unless the table above says
so. A `ClickDetector.MouseClick` is handed a Player and a `ProximityPrompt.PromptShown` an
input type; the adapters drop both, because adoption is client-only and the player would
always be this one.

### The same table, by class

`Added` and `Removed` are omitted because every row has them — including a Folder or a Part
with no adapter at all, which is why a query carrying only those two can select anything.

| Class | Handlers |
| --- | --- |
| `Frame`, `ViewportFrame` | `Hover`, `Unhover`, `Press`, `Release` |
| `TextLabel`, `ImageLabel`, `ScrollingFrame`, `CanvasGroup`, `VideoFrame` | those four, plus `Changed` |
| `TextButton`, `ImageButton` | those four, plus `Active`, `Secondary`, `Changed` |
| `TextBox` | those four, plus `Focus`, `Blur`, `Submit`, `Changed` |
| `ScreenGui`, `SurfaceGui`, `BillboardGui` | `Changed` *(Enabled)* only — a LayerCollector is not a GuiObject |
| `UICorner`, `UIScale` | `Changed` only |
| every other `UI*` | none |
| `ClickDetector` | `Active`, `Secondary`, `Hover`, `Unhover` — **no** `Press` / `Release`, **no** `Changed` |
| `ProximityPrompt` | `Active`, `Hover`, `Unhover`, `Press`, `Release` — **no** `Secondary`, **no** `Changed` |

### Code raises; attributes warn

Binding a handler an element cannot support is never a silent no-op, but the severity depends
on who asked. `Unrest:Query(…, { Submit = … })` against a Frame **throws**; the same mistake
expressed in Studio **warns**, names the element and the fix, and leaves the screen up. Both
go through `Adapters.bind` and print the same sentence — see §8.

Note which side you are on: **exactly one handler is reachable from an attribute at all.**
`UnrestCommand` wires `Active`, and there is no `UnrestHover` or `UnrestSubmit`. So the warn
path only ever covers `UnrestCommand` on a class that cannot be activated; every other name in
this section is code-only and therefore always raises.

### The traps

These are the parts that cost an afternoon if nobody wrote them down.

#### `Press` fires, `Release` may never fire

Both are `GuiObject.InputBegan` / `InputEnded`, and **`InputEnded` only fires while the
pointer is still over that instance.** Press a button, drag off it, release: `Press` fired and
`Release` never will. Anything built as a drag on top of this pair — a slider, a
hold-to-charge action, a "pressed" tint — ends up with a state stuck until the next `Press`.

The adapter will not fix this for you, on purpose: papering over it means connecting
`UserInputService` on the element's behalf, and a global input listener is not something a tag
should silently buy you.

The same shape of failure has three more causes, so treat them as one rule rather than four:

| Cause | What is lost |
| --- | --- |
| pointer leaves the element while held | `Release` |
| a channel writes `Visible = false` on a hovered or held element | `Unhover`, `Release` |
| the element is released mid-gesture — untagged, `UnrestIgnore` ticked, reparented out | every handler at once; the connections are torn down where they stand |
| the element is destroyed mid-gesture | same |

> **Never store "is pressed" or "is hovered" as state that a later event has to clear.** Drive
> the visual from the enter event alone, or reset it in `Removed` — which is the one departure
> the framework does guarantee, exactly once, for every one of those causes.

#### `Focus`/`Blur` and `Press`/`Release` are not the only asymmetric pair

`Hover`/`Unhover` on a `GuiObject` is `MouseEnter`/`MouseLeave`, which is **mouse-only**: it
never fires on a touch device, so a hover-only affordance is invisible on mobile. It also does
not fire when the element moves or disappears out from under a stationary cursor.

`Hover` on a `ProximityPrompt` is not a pointer event at all. `PromptShown` fires when the
prompt becomes visible — proximity and line of sight — and re-fires every time the player
walks back into range. If you want "is being pointed at", `Hover` means that on a GuiObject
and on a ClickDetector, and something else entirely on a prompt.

#### `Press` on a `ProximityPrompt` is silent by default

`PromptButtonHoldBegan` / `PromptButtonHoldEnded` only exist when `HoldDuration > 0`. With the
default of zero, `Press` and `Release` bind successfully and then never fire once, while
`Active` fires normally. `HoldDuration` is a bindable property, so a channel can switch that
pair on and off from the server without anything rebinding.

#### `Changed` is synthesised, and a class either has a value or it does not

`Changed` is not written by hand in any adapter. The registry manufactures it from the
adapter's `ValueProperty`, so a class has `Changed` exactly when it has one obvious value:

| Has a `ValueProperty`, so has `Changed` | The property |
| --- | --- |
| `TextLabel`, `TextButton`, `TextBox` | `Text` |
| `ImageLabel`, `ImageButton` | `Image` |
| `ScrollingFrame` | `CanvasPosition` |
| `CanvasGroup` | `GroupTransparency` |
| `VideoFrame` | `Video` |
| `LayerCollector` — so `ScreenGui`, `SurfaceGui`, `BillboardGui` | `Enabled` |
| `UICorner` | `CornerRadius` |
| `UIScale` | `Scale` |

Everything else refuses `Changed` loudly, and the refusals are the deliberate part: `Frame`
and `ViewportFrame` have no one value, `UIListLayout` has nine and picking one would be a coin
flip dressed as an event, and `ClickDetector` / `ProximityPrompt` have none at all.
`ValueProperty` flattens down the `Extends` chain like everything else and **cannot be
un-declared**, which is why `ScreenGui` reports `Enabled` without saying so itself.

Three more things about the value it reports:

* It is the property's **current** value, read back when the signal fires, because
  `GetPropertyChangedSignal` carries no payload. Two writes in the same frame can report the
  later value twice, and there is never a previous value to compare against.
* It fires for writes **the framework itself makes**. `UnrestBind` defaults to the very
  property `Changed` watches, so an element that both follows a channel and handles `Changed`
  hears its own repaint — and a `Changed` that dispatches back into that channel is a loop.
* On a `TextBox` it fires per keystroke. That is what `Submit` exists to avoid.

#### `Active` means two unrelated things

It is a **handler** name on `GuiButton` (`Events.Active`) and a **bindable property** name on
`GuiBase2d` (`Bindable.Active`). So:

```luau
adapters:Supports(label, "Active")   --> false — a TextLabel cannot be activated
adapters:CanBind(label, "Active")    --> true  — but its Active property may be written
```

Two questions, one string, opposite answers. This is also why a `Describe` message can list
`Active` under *bindable properties* for an element that does not support the `Active`
*handler*, which reads like a contradiction and is not.

The two also interact. `Activated` does not fire while the `Active` property is false, so a
channel bound to `Active` can silence the `Active` handler — with `Press` and `Release` still
firing, since those are `InputBegan`/`InputEnded` and do not consult it. `Modal` on another
button does the same thing, from a different instance entirely.

#### `Submit` and `Blur` fire in an undefined order

Every commit is also a blur: pressing Enter fires both, from two separate connections to the
same `FocusLost`. The connections are made while iterating a hash table, so their relative
order is not defined and neither handler may assume the other has run. Use `Blur` for "no
longer being edited" and `Submit` for the value. Clicking away and pressing Escape both fire
`Blur` alone — neither is a commit.

#### `Added` fires during `Query`, but never during `Bind`

`Added` fires for elements that **already match** when the query is created — synchronously,
inside the `Unrest:Query` call, before the handle is returned:

```luau
local handle
handle = unrest:Query({ Tag = "Unrest" }, {
    Added = function(element)
        print(handle)   --> nil, for every element that already existed
    end,
})
```

`QueryHandle:Bind` is the asymmetry to watch. Merging an `Added` in later rebinds every
element's connections but fires `Added` for **none** of them, because they had already
arrived. If you need it for the existing set, pass it in the initial `Query` call.

`Removed`, by contrast, fires exactly once per departure — including once for every current
element when the query is `:Destroy()`ed. It runs *after* the element's event connections are
torn down, so the element is already inert by then; when the cause was `Destroying`, the
instance is on its way out, so do the cleanup there and then rather than deferring it.

---

## 4. Adapter coverage

Adapters compose along Roblox's own class hierarchy through `Extends`, so each row below
lists only what that class **adds**. Resolution picks the most specific registered adapter
the instance `:IsA()`, flattens the chain (derived wins), and caches the result per
ClassName.

### 2D base

| Class | Extends | Adds handlers | Adds bindable properties |
| --- | --- | --- | --- |
| `GuiBase2d` | — | — | `Active`, `AutoLocalize`, `Selectable` |
| `GuiObject` | `GuiBase2d` | `Hover`, `Unhover`, `Press`, `Release` | `Visible`, `Position`, `Size`, `AnchorPoint`, `AutomaticSize`, `Rotation`, `LayoutOrder`, `ZIndex`, `ClipsDescendants`, `BackgroundColor3`, `BackgroundTransparency`, `BorderColor3`, `BorderSizePixel` |

### Buttons

| Class | Extends | Adds handlers | Adds bindable properties |
| --- | --- | --- | --- |
| `GuiButton` | `GuiObject` | `Active`, `Secondary` | `AutoButtonColor`, `Modal`, `Selected` |
| `TextButton` | `GuiButton` | `Changed` *(Text)* | the text set † |
| `ImageButton` | `GuiButton` | `Changed` *(Image)* | the image set ‡, `HoverImage`, `PressedImage` |

`Active` binds to `Activated` rather than `MouseButton1Click` on purpose: `Activated`
already folds mouse, touch and gamepad into one event, and already respects `Modal` and
`Active`.

### Text

| Class | Extends | Adds handlers | Adds bindable properties |
| --- | --- | --- | --- |
| `TextLabel` | `GuiObject` | `Changed` *(Text)* | the text set † |
| `TextBox` | `GuiObject` | `Focus`, `Blur`, `Submit`, `Changed` *(Text)* | the text set †, `PlaceholderText`, `PlaceholderColor3`, `ClearTextOnFocus`, `MultiLine`, `TextEditable` |

### Frames and displays

| Class | Extends | Adds handlers | Adds bindable properties |
| --- | --- | --- | --- |
| `Frame` | `GuiObject` | — | `Style` |
| `ScrollingFrame` | `GuiObject` | `Changed` *(CanvasPosition)* | `CanvasPosition`, `CanvasSize`, `AutomaticCanvasSize`, `ScrollingEnabled`, `ScrollingDirection`, `ScrollBarThickness`, `ScrollBarImageColor3`, `ScrollBarImageTransparency`, `ElasticBehavior`, `HorizontalScrollBarInset`, `VerticalScrollBarInset` |
| `CanvasGroup` | `GuiObject` | `Changed` *(GroupTransparency)* | `GroupColor3`, `GroupTransparency` |
| `ViewportFrame` | `GuiObject` | — | `Ambient`, `CurrentCamera`, `ImageColor3`, `ImageTransparency`, `LightColor`, `LightDirection` |
| `VideoFrame` | `GuiObject` | `Changed` *(Video)* | `Video`, `Playing`, `Looped`, `TimePosition`, `Volume` |
| `ImageLabel` | `GuiObject` | `Changed` *(Image)* | the image set ‡ |

### Layer collectors

A `LayerCollector` is a `GuiBase2d` but **not** a `GuiObject`, which is exactly why it has
no pointer events. A ScreenGui has no `MouseEnter` and no `BackgroundColor3`; declaring
either would be a promise the class cannot keep.

| Class | Extends | Adds handlers | Adds bindable properties |
| --- | --- | --- | --- |
| `LayerCollector` | `GuiBase2d` | `Changed` *(Enabled)* | `Enabled`, `ResetOnSpawn`, `ZIndexBehavior` |
| `ScreenGui` | `LayerCollector` | — | `DisplayOrder`, `IgnoreGuiInset`, `ClipToDeviceSafeArea`, `SafeAreaCompatibility`, `ScreenInsets` |
| `SurfaceGui` | `LayerCollector` | — | `Adornee`, `Face`, `AlwaysOnTop`, `Brightness`, `LightInfluence`, `MaxDistance`, `PixelsPerStud`, `SizingMode`, `CanvasSize`, `ClipsDescendants` |
| `BillboardGui` | `LayerCollector` | — | `Adornee`, `Size`, `AlwaysOnTop`, `Brightness`, `LightInfluence`, `MaxDistance`, `StudsOffset`, `StudsOffsetWorldSpace`, `ExtentsOffset`, `ExtentsOffsetWorldSpace`, `ClipsDescendants` |

### UI modifiers

None of these has an event, which is the point: a `UIPadding` cannot be activated, so
`UnrestCommand` on one is a warning rather than a mystery. What they do have is layout you
can drive from a channel.

| Class | Extends | Adds bindable properties |
| --- | --- | --- |
| `UIBase` | — | — |
| `UIComponent` | `UIBase` | — |
| `UILayout` | `UIComponent` | — |
| `UIGridStyleLayout` | `UILayout` | `FillDirection`, `HorizontalAlignment`, `VerticalAlignment`, `SortOrder` |
| `UIListLayout` | `UIGridStyleLayout` | `Padding`, `Wraps`, `ItemLineAlignment`, `HorizontalFlex`, `VerticalFlex` |
| `UIGridLayout` | `UIGridStyleLayout` | `CellSize`, `CellPadding`, `FillDirectionMaxCells`, `StartCorner` |
| `UIPageLayout` | `UIGridStyleLayout` | `Animated`, `Circular`, `EasingDirection`, `EasingStyle`, `GamepadInputEnabled`, `Padding`, `ScrollWheelInputEnabled`, `TouchInputEnabled`, `TweenTime` |
| `UITableLayout` | `UIGridStyleLayout` | `FillEmptySpaceColumns`, `FillEmptySpaceRows`, `MajorAxis`, `Padding` |
| `UIConstraint` | `UIComponent` | — |
| `UIAspectRatioConstraint` | `UIConstraint` | `AspectRatio`, `AspectType`, `DominantAxis` |
| `UISizeConstraint` | `UIConstraint` | `MaxSize`, `MinSize` |
| `UITextSizeConstraint` | `UIConstraint` | `MaxTextSize`, `MinTextSize` |
| `UIPadding` | `UIComponent` | `PaddingTop`, `PaddingBottom`, `PaddingLeft`, `PaddingRight` |
| `UICorner` | `UIComponent` | `CornerRadius` — plus `Changed` |
| `UIGradient` | `UIComponent` | `Color`, `Enabled`, `Offset`, `Rotation`, `Transparency` |
| `UIStroke` | `UIComponent` | `ApplyStrokeMode`, `Color`, `Enabled`, `LineJoinMode`, `Thickness`, `Transparency` |
| `UIScale` | `UIComponent` | `Scale` — plus `Changed` |
| `UIFlexItem` | `UIComponent` | `FlexMode`, `GrowRatio`, `ShrinkRatio`, `ItemLineAlignment`, `FillEmptySpace` |

### 3D interaction surfaces

Not GUI, and they draw nothing — but designers tag them for exactly the same reason they tag
a button, and expect `Active` to mean "the player did the thing" in both cases. Speaking the
same handler vocabulary is what lets one query select *every activatable element in this
room* without caring how it is activated.

| Class | Handlers | Bindable properties |
| --- | --- | --- |
| `ClickDetector` | `Active` *(MouseClick)*, `Secondary` *(RightMouseClick)*, `Hover` / `Unhover` *(MouseHoverEnter/Leave)* | `MaxActivationDistance`, `CursorIcon` |
| `ProximityPrompt` | `Active` *(Triggered)*, `Hover` / `Unhover` *(PromptShown/PromptHidden)*, `Press` / `Release` *(PromptButtonHoldBegan/Ended)* | `ActionText`, `ObjectText`, `Enabled`, `HoldDuration`, `MaxActivationDistance`, `RequiresLineOfSight`, `KeyboardKeyCode`, `GamepadKeyCode`, `ClickablePrompt`, `Exclusivity`, `Style`, `UIOffset` |

A `ClickDetector` has no down/up pair, so binding `Press` to one is an error rather than a
lie.

> † **the text set** — `Text`, `TextColor3`, `TextTransparency`, `TextScaled`, `TextSize`,
> `TextWrapped`, `TextTruncate`, `TextXAlignment`, `TextYAlignment`, `TextStrokeColor3`,
> `TextStrokeTransparency`, `RichText`, `FontFace`, `LineHeight`, `MaxVisibleGraphemes`.
>
> ‡ **the image set** — `Image`, `ImageColor3`, `ImageTransparency`, `ImageRectOffset`,
> `ImageRectSize`, `ScaleType`, `SliceCenter`, `SliceScale`, `TileSize`, `ResampleMode`.

---

## 5. `Bindable` is an allowlist, on purpose

A channel value can arrive from the server. If `UnrestBind` accepted any property name, a
published string would be one attribute away from writing `Parent`, `Adornee` or
`CurrentCamera` on an arbitrary instance. So each adapter declares, by hand, the properties
a channel value may write — and everything else is refused with a warning that names the
element, its class, and what that class *does* support.

`ValueProperty` is the related idea in the other direction: the one property that means
"this element's value". It is what `UnrestBind` defaults to, what `Changed` watches, and
what `Submit` reports. The registry **synthesises** a `Changed` binder from it, so an adapter
that says `ValueProperty = "Text"` gets `Changed` for free and the two can never drift apart.

A class only gets a `ValueProperty` when it genuinely has one obvious value. `Frame` has
none, and binding `Changed` to a Frame is therefore a mistake worth hearing about rather
than a subscription to nothing. `UICorner` and `UIScale` have exactly one property each, so
they do; `UIListLayout` has nine, so it does not.

---

## 6. Code-driven binding — `Unrest:Query`

Attributes cover the common cases. `Unrest:Query` covers the rest: reading a channel before
deciding which command to send, reacting to hover, or binding a whole group at once.

```luau
local toggle = unrest:Query({
    Tag = "Unrest",
    Selector = "GuiButton",   -- is:A("GuiButton") -- TextButton and ImageButton both
    Role = "ToggleMenu",
}, {
    Active = function(element)
        local playing = unrest.Bridge:Peek("Music.NowPlaying")
        if playing == nil then
            unrest:Dispatch("Music.Play", "Lobby")
        else
            unrest:Dispatch("Music.Stop", nil)
        end
    end,

    Hover = function(element) end,
    Added = function(element) end,
})
```

### Descriptor

| Field | Type | Meaning |
| --- | --- | --- |
| `Tag` | `string?` | CollectionService tag. Drives live binding via `GetInstanceAddedSignal` / `GetInstanceRemovedSignal`. `"Unrest"` **cascades** — see below. Any other tag is exact. |
| `Selector` | `string?` | ClassName tested with `:IsA()`. Abstract classes work: `"GuiButton"`, `"GuiObject"`. |
| `Name` | `string?` | Exact `Instance.Name`. Re-evaluated live on rename. |
| `Role` | `string?` | `UnrestRole`, **falling back to `Instance.Name`**. Re-evaluated live. |
| `Group` | `string?` | `UnrestGroup`. No fallback. Re-evaluated live. |
| `Ancestor` | `Instance?` | Search root. Required when there is no `Tag`. |
| `Recursive` | `boolean?` | Search descendants rather than only children. Defaults to `true`. |

At least one of `Tag` / `Selector` / `Name` / `Role` / `Group` must be present, and a
descriptor without a `Tag` must supply an `Ancestor` — a tagless, rootless query would have
to walk the whole DataModel.

> **`Tag = "Unrest"` selects what the framework manages, not what somebody tagged.** A
> button adopted by cascade is a button this query finds; `Selector.isManaged` is the single
> definition of that, and `Elements` adopts with the very same predicate. Sourcing from the
> raw `GetTagged` list instead would leave cascaded elements adopted, wired, and invisible to
> the query that asked for them — worse than never adopting them.
>
> Only the framework's own tag cascades. `Tag = "Highlighted"` still means exactly the
> instances carrying that tag: a foreign tag is a label, not an opt-in.

**Prefer `Role` over `Name`.** `Name` is what a designer changes the afternoon after you
ship; `UnrestRole` is a contract they set deliberately. Because `Role` falls back to the
name, a button simply called `ToggleMenu` matches today and keeps matching after somebody
renames it to `Btn_04_final` and sets `UnrestRole` instead.

### Handle

| Member | Notes |
| --- | --- |
| `:Elements()` | snapshot copy — safe to mutate |
| `:Count()` | |
| `:Each(visitor)` | chainable; iterates a snapshot |
| `:Bind(handlers)` | merges handlers in and **rebuilds** every element's connections, so replacing `Active` never leaves the old one attached |
| `:Destroy()` | releases everything and fires `Removed` for each current element |
| `.ElementAdded` / `.ElementRemoved` | `Signal<Instance>` |

A query sources its own candidates straight from CollectionService, so it works before
`Start` and keeps working after. Its lifetime is yours: call `:Destroy()` when the screen it
serves goes away.

### Why this is not a scan

Each query keeps two sets. **Watched** is every candidate the source can produce; each one
carries a small maid holding a `Destroying` connection plus *exactly* the watches this
descriptor needs — a `Name` or `Role` filter earns a `Name` watch, a `Role` or `Group`
filter earns an attribute watch, a class-only filter earns neither. **Bound** is the subset
that currently matches, each with a maid holding its handler connections.

So an element may join and leave the result set any number of times over its life, and
`Removed` fires exactly once per departure.

A query sourcing the framework tag adds the cascade's own liveness on top: one
`DescendantAdded` per tagged root, one `UnrestIgnore` watch per gate, and — per candidate —
an `AncestryChanged` and an `UnrestIgnore` watch, because those two edits are exactly the
ones that can move an element in or out of *coverage* rather than out of the filter. A
descriptor naming any other tag, or an `Ancestor`, pays none of that.

---

## 7. Registering an adapter

Any class the framework has never heard of — a custom one, or a Roblox class added after
this version shipped — is one call away:

```luau
unrest.Adapters:Register({
    ClassName = "UIDragDetector",
    Extends = "UIComponent",
    Events = {
        Press = function(element, invoke)
            return (element :: UIDragDetector).DragStart:Connect(function()
                invoke(nil)
            end)
        end,
    },
    Bindable = { Enabled = true, DragStyle = true },
})
```

| Field | Meaning |
| --- | --- |
| `ClassName` | the Roblox ClassName this adapter teaches |
| `Extends` | the adapter it composes on — usually the superclass |
| `Events` | handler name → `(element, invoke) -> RBXScriptConnection?` |
| `Bindable` | property allowlist |
| `ValueProperty` | the property `Changed` watches and `UnrestBind` defaults to |

Registering replaces any adapter for the same ClassName and invalidates the resolution
cache, so it takes effect immediately — including for elements already adopted, the next
time they are resolved. Register a base **before** the adapter that extends it; otherwise the
chain warns and stops short.

Even without registering anything, an unknown class still resolves usefully: the registry
picks the most specific ancestor it *does* know. A `UIDragDetector` with no adapter of its
own resolves to `UIComponent`, and a hypothetical new `GuiObject` subclass gets the whole
pointer vocabulary for free.

---

## 8. The errors you will see

Binding a handler an element cannot support is never a silent no-op.

```
[Unrest.Adapters] handler "Submit" cannot bind to game.Players.You.PlayerGui.Menu.Title:
a TextLabel resolves to TextLabel <- GuiObject <- GuiBase2d and supports handlers: Changed,
Hover, Press, Release, Unhover -- bindable properties: Active, AnchorPoint, ... Narrow the
query {Tag = "Unrest", is:A("GuiObject")} with a Selector or a Role, or drop that handler.
```

```
[Unrest.Elements] game.Workspace.Door.Prompt sets UnrestBind = "Parent", which is not
bindable: a ProximityPrompt resolves to ProximityPrompt and supports handlers: Active,
Hover, Press, Release, Unhover -- bindable properties: ActionText, ClickablePrompt, ...
Bindable is an allowlist, so a channel value can never write an arbitrary property;
register an adapter that permits it if you need it.
```

**Code raises; attributes warn.** Code that binds a handler its element cannot support is a
bug and should stop. An attribute that asks for the same thing is *data*, usually typed by
somebody who is not looking at the output window, and taking the rest of the screen down
with it would be the worse outcome. Same message, different severity.

The `Resolver` checks descriptors, handler tables and adapter definitions at runtime, because
Luau's type checker only protects callers that are themselves typed:

```
[Unrest.Resolver] unknown Query descriptor field "Rôle". Did you mean "Role"?
Valid fields: Ancestor, Group, Name, Recursive, Role, Selector, Tag.
```

---

## 9. Source map

| File | Role |
| --- | --- |
| `src/shared/Adapters/init.luau` | the AdapterRegistry: resolution, flattening, caching, and `Adapters.bind` |
| `src/shared/Adapters/Types.luau` | the adoption type surface |
| `src/shared/Adapters/Selector.luau` | descriptor compilation, the match predicate, and the cascade rule (`isManaged` / `cascadeUnder` / `isGate`) |
| `src/shared/Adapters/Query.luau` | the live query engine |
| `src/shared/Adapters/Classes/*.luau` | one file per class family |
| `src/shared/Elements/init.luau` | the ElementManager: adoption, attribute resolution and wiring |
| `src/shared/Presets.luau` | the named attribute bundles `UnrestPreset` expands into |
| `src/shared/Util/Resolver.luau` | runtime validation of the public boundary |
| `src/client/init.client.luau` | the worked example — adopts what is tagged, builds nothing |
