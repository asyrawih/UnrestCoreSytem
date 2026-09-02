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

Changing any of them re-wires **that element only**, live, through
`GetAttributeChangedSignal`. Editing `UnrestFormat` in Studio while the game runs repaints
the label on the next publish; you do not restart anything.

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

Handlers are the same eight verbs whatever the class underneath is, plus two that describe
the query rather than the element.

| Handler | Signature | Fires on |
| --- | --- | --- |
| `Active` | `(element, nil)` | primary activation — `Activated`, `MouseClick`, `Triggered` |
| `Secondary` | `(element, nil)` | `MouseButton2Click`, `RightMouseClick` |
| `Press` | `(element, nil)` | pointer down (`InputBegan`, filtered to MouseButton1 / Touch) |
| `Release` | `(element, nil)` | pointer up (`InputEnded`, same filter) |
| `Hover` | `(element, nil)` | `MouseEnter`, `MouseHoverEnter`, `PromptShown` |
| `Unhover` | `(element, nil)` | `MouseLeave`, `MouseHoverLeave`, `PromptHidden` |
| `Focus` | `(element, nil)` | `TextBox.Focused` |
| `Blur` | `(element, nil)` | `TextBox.FocusLost` |
| `Submit` | `(element, text)` | `TextBox.FocusLost` **with Enter pressed** — clicking away is not a commit |
| `Changed` | `(element, value)` | the adapter's `ValueProperty` changed |
| `Added` | `(element, nil)` | the element started matching the descriptor |
| `Removed` | `(element, nil)` | it stopped matching — untagged, renamed, reparented, or destroyed |

`Added` and `Removed` are supported by *every* element, including the ones that support
nothing else: they describe the query's lifecycle, not the instance's.

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
| `Tag` | `string?` | CollectionService tag. Drives live binding via `GetInstanceAddedSignal` / `GetInstanceRemovedSignal`. |
| `Selector` | `string?` | ClassName tested with `:IsA()`. Abstract classes work: `"GuiButton"`, `"GuiObject"`. |
| `Name` | `string?` | Exact `Instance.Name`. Re-evaluated live on rename. |
| `Role` | `string?` | `UnrestRole`, **falling back to `Instance.Name`**. Re-evaluated live. |
| `Group` | `string?` | `UnrestGroup`. No fallback. Re-evaluated live. |
| `Ancestor` | `Instance?` | Search root. Required when there is no `Tag`. |
| `Recursive` | `boolean?` | Search descendants rather than only children. Defaults to `true`. |

At least one of `Tag` / `Selector` / `Name` / `Role` / `Group` must be present, and a
descriptor without a `Tag` must supply an `Ancestor` — a tagless, rootless query would have
to walk the whole DataModel.

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
| `src/shared/Adapters/Selector.luau` | descriptor compilation and the match predicate |
| `src/shared/Adapters/Query.luau` | the live query engine |
| `src/shared/Adapters/Classes/*.luau` | one file per class family |
| `src/shared/Elements/init.luau` | the ElementManager: adoption and attribute wiring |
| `src/shared/Util/Resolver.luau` | runtime validation of the public boundary |
| `src/client/init.client.luau` | the worked example — adopts what is tagged, builds nothing |
