# Proposal — Controls

**Status: proposal only. Nothing here is implemented. Do not build it until asked.**

## 1. The problem

> "The point of building the framework is that when I redesign the UI, the core system is
> the same. So I need one easy thing for when I switch UI. Say I build a slider — when I
> rework the UI, the implementation changes again. I need a high-level API for this."

The framework already keeps a redesign from touching the *core*: systems publish channels and
handle commands, and they never learn what a button looks like. What it does not yet protect
is the layer in between. A slider is not an element. It is a Frame that defines an axis, a
knob you drag, a fill that follows, and a label that reports — four instances that only mean
"slider" when something knows how they relate.

Today that knowledge has to live in a script, written against one particular tree:

```luau
local track = panel.Volume.Track
local knob = track.Knob
knob.InputBegan:Connect(function(input) ... end)
-- and a dozen more lines computing a fraction from AbsolutePosition
```

Rework the design — knob inside the fill, track rotated, label moved out to a corner — and
every line above is wrong. The core survived the redesign; the glue did not.

## 2. Why the pieces we have do not cover it

| Piece | What it handles | Why it is not enough |
| --- | --- | --- |
| Tag + adapters | one instance, its events, its bindable properties | a slider is four instances that must be related |
| `UnrestCommand` / `UnrestChannel` | one element ↔ one command or channel | cannot express "drag this, scaled against that" |
| `Unrest:Query` | *finding* instances without hardcoded paths | you still write the behaviour yourself, per screen |
| Presets | collapsing repeated attributes | a bundle of attributes, not a behaviour |

`Query` solves half the problem already: it finds things by role instead of by path. What is
missing is that **the behaviour is written once, by the framework, instead of once per screen.**
That is the high-level API being asked for.

## 3. The acceptance test

Everything below should be judged against one scenario:

> Build `MenuV1` in Studio with a slider. Ship it. Later build `MenuV2` from scratch — a
> different layout, different classes, a vertical slider instead of a horizontal one. Delete
> `MenuV1`, drop in `MenuV2`, press Play.
>
> **Zero lines of Luau change. No system, no bootstrap, no contract.**

If a proposed design cannot pass that, it is the wrong design.

## 4. The model

Three ideas, in order of size.

**A control is a named behaviour over a subtree.** `UnrestControl = "Slider"` on a Frame says
"the framework owns the behaviour of this subtree, and that behaviour is a slider". The
framework supplies the dragging, the arithmetic, the painting and the dispatching.

**A part is an instance playing a named role inside that subtree.** The control finds its
parts by role, never by path. Move a part, rename its instance, reparent it three levels
deeper — as long as it still declares the role, the control still finds it.

**A part is required to have a capability, not a class.** The knob needs to report press and
release. That is a question the adapter registry already answers (`Supports`), for every class
it knows. So a knob may be a `TextButton`, an `ImageButton`, or anything else whose adapter
declares `Press`. The fill needs a writable `Size`, which is `CanBind`. Controls state what
they need; the existing capability model decides which classes qualify.

The third idea is what makes redesign safe. A control that demanded `ImageButton` would break
the moment a designer preferred a `TextButton`.

## 5. Attribute surface

On the control root:

| Attribute | Meaning |
| --- | --- |
| `UnrestControl` | the control's name, e.g. `"Slider"`. Declares the subtree. |
| `UnrestChannel` | channel the control reads its value from. Retained, so it paints correctly on the first frame. |
| `UnrestCommand` | command dispatched when the user changes the value. |
| `UnrestMin` / `UnrestMax` | value domain. Default `0` and `1`. |
| `UnrestStep` | quantisation. Default `0`, meaning continuous. |
| `UnrestFormat` | format for the `Value` part, e.g. `"{value}%"`. |

On each part, one attribute:

| Attribute | Meaning |
| --- | --- |
| `UnrestPart` | the role this instance plays inside its control, e.g. `"Track"`. |

`UnrestPart` is deliberately **not** `UnrestRole`. Role is identity in the whole DataModel and
is what `Query` selects on; part is a position inside one control. Overloading one attribute
with both meanings would make a knob named `Knob` in two different sliders collide in a query,
and would make the control resolution depend on global uniqueness it cannot enforce.

## 6. Worked example

### V1 — horizontal

```
Volume (Frame)          UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
                        UnrestFormat  = "Volume {value}%"
  Track (Frame)         UnrestPart = "Track"
    Fill (Frame)        UnrestPart = "Fill"
    Knob (ImageButton)  UnrestPart = "Knob"
  Readout (TextLabel)   UnrestPart = "Value"
```

One tag on an ancestor, four `UnrestPart` attributes, four control attributes. No code.

### V2 — the redesign

Vertical. The knob is now a `TextButton`. The fill is a `CanvasGroup`. The readout moved
inside the track. The instances are renamed to suit the new design.

```
VolumeDial (Frame)      UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
                        UnrestFormat  = "Volume {value}%"
  Column (Frame)        UnrestPart = "Track"
    Level (CanvasGroup) UnrestPart = "Fill"
    Grip (TextButton)   UnrestPart = "Knob"
    Number (TextLabel)  UnrestPart = "Value"
```

Different classes, different names, different tree, different axis. **The four control
attributes are identical and no Luau changed.** That is the whole proposal in one diff.

Orientation is inferred from the Track's `AbsoluteSize` — taller than wide means vertical —
with `UnrestOrientation` available when a square track makes inference a coin toss.

## 7. Built-in catalogue

Each ships with a part contract. `req` means the control refuses to run without it.

| Control | Parts | Capability each part needs |
| --- | --- | --- |
| `Slider` | Track `req`, Knob, Fill, Value | Track: any GuiObject. Knob: `Press`. Fill: bindable `Size`. Value: a bindable text property. |
| `Toggle` | Button `req`, On, Off, Value | Button: `Active`. On/Off: bindable `Visible`. |
| `Stepper` | Increment `req`, Decrement `req`, Value | buttons: `Active`. Value: bindable text. |
| `ProgressBar` | Track `req`, Fill `req`, Value | as Slider, minus the input. |
| `TabGroup` | Tab `req` (many), Panel (many, matched by a key) | Tab: `Active`. Panel: bindable `Visible`. |

`ProgressBar` is `Slider` with the input removed, and shipping both makes the distinction
explicit rather than a matter of whether you remembered to add a knob.

## 8. Resolution and liveness

Part resolution follows the rule already established twice in this codebase: **one definition,
used by everyone who needs the answer.** `Selector.ancestorChain` is the precedent — `Elements`
resolves with it and `Query` watches the chain it returns, so the two cannot disagree.

- A control resolves parts by scanning its own subtree for `UnrestPart`, nearest first.
- A nested control's subtree is excluded from its ancestor's scan. A slider inside a tab panel
  belongs to the slider.
- Two instances claiming the same part is a warning, and the nearest wins. Silently picking one
  at random is how a redesign breaks a week later.
- Parts are watched live. A part added, removed, renamed or reparented re-resolves the control,
  because that is exactly what happens while somebody is designing with the game running.

## 9. What happens when it is wrong

The convention this codebase already uses is **code raises, attributes warn**, and it applies
here unchanged. A control is declared in Studio by somebody not watching the output window, so
a broken control must never take the screen down.

| Situation | Behaviour |
| --- | --- |
| Missing a required part | warn once, naming the control, the missing part and the subtree. The control stays inert. |
| Optional part absent | silent. A slider with no Value label is a slider with no label. |
| Part cannot do what the control needs | warn, naming the instance, its class, and which classes qualify. Reuses the adapter registry's existing `Describe`. |
| Unknown control name | warn, listing the registered controls. |
| Part disappears at runtime | required: revert to inert and warn. Optional: stop driving it. |

Plus a validator, `Controls:Validate(screenGui)`, returning a report rather than warnings — so
a redesign can be checked before pressing Play, and later wired to a button in the Studio
plugin.

## 10. Throttling, and why the contract already knows the answer

A dragged slider produces input every frame. Dispatching each one would spend a player's rate
limit in well under a second, and the server would start refusing — the framework fighting its
own security layer.

The fix is already in the codebase. `Music.SetVolume` declares `RateLimit = { Count = 8,
Window = 1 }` in `Net/Contracts.luau`. A control can **read its own command's contract** and
throttle to it, rather than shipping a magic number that drifts out of step with the server.

The proposed shape:

- paint locally at full rate, so dragging feels immediate;
- dispatch at the contract's rate, minus a margin;
- always dispatch a final value on release, so the authoritative state matches what the player
  let go of.

This is worth stating loudly: it means a control's network behaviour is derived from the same
declaration the server enforces, and the two cannot drift.

## 11. Code API

Controls are declarative first, but code must be able to reach one without knowing its visuals.

```luau
local volume = unrest:Control("VolumeDial")   -- by the root's UnrestRole, or its name

volume:Get()                 -- current value
volume:Set(0.4)              -- paint and dispatch, as if the player had done it
volume.Changed:Connect(fn)   -- fires on user change, not on channel echo
volume:Parts()               -- the resolved parts, for the rare case that needs them
```

`Changed` firing only on user change matters: a control that fired on its own channel echo
would loop the moment somebody subscribed and republished.

Registering a custom control mirrors `Adapters:Register`:

```luau
unrest.Controls:Register({
    Name = "RadialDial",
    Parts = {
        Ring = { Required = true },
        Needle = { Required = true, Needs = "Press" },
        Value = { Bindable = "Text" },
    },
    Attach = function(control) ... end,   -- returns a teardown
})
```

Custom controls must be as cheap to write as built-ins, or every design that does not fit the
catalogue falls back to hand-written glue and the proposal has failed.

## 12. How it composes with what exists

- **Tag** — unchanged. A control root must be inside a managed subtree; the cascading tag
  already covers everything below it.
- **Adapters** — reused for capability checks and for driving parts. No new per-class knowledge.
- **Attributes and inheritance** — `UnrestControl` is per-element intent, so it is **not**
  inheritable. `UnrestFormat` on a control root applies to the Value part, which is a small
  overload worth calling out.
- **Presets** — a preset may declare a control's attributes, so `UnrestPreset = "VolumeSlider"`
  can carry the channel, command, domain and format together. This is where presets pay off most.
- **Bridge and contracts** — unchanged. A control dispatches the same commands through the same
  gate. **A control grants no privilege**, exactly as an attribute does not.
- **Query** — unchanged and still the escape hatch for behaviour no control expresses.

## 13. Implementation phases

| Phase | Delivers | Proves |
| --- | --- | --- |
| 1 | Control registry, part resolution, liveness, failure behaviour, and `Slider` | the model works on the hardest common case |
| 2 | `Toggle`, `Stepper`, `ProgressBar` | the machinery generalises and new controls are cheap |
| 3 | `unrest:Control()`, `Controls:Validate()`, plugin lint button | the redesign workflow, not just the runtime |
| 4 | `TabGroup`, custom-control authoring guide | extensibility beyond the catalogue |

Phase 1 is the only one worth committing to now. If the slider does not survive a real
redesign, phases 2 to 4 are building on sand.

## 14. What this does not solve

Honesty about the boundary, so the proposal is not oversold:

- **Layout and styling are still yours.** Controls drive behaviour; they never set a colour, a
  corner radius, or a position that is not part of the value they represent.
- **A design with no equivalent part is not covered.** A slider whose value is expressed as a
  hue rather than a length has no `Fill`; it needs a custom control. The catalogue is a floor.
- **Animation is out of scope** for phase 1. Controls set values; tweening them is a separate
  concern and folding it in early would couple two things that change at different rates.
- **It adds concepts.** Tag, attribute, preset, and now control and part. The bet is that a
  control removes more glue than the concept costs. If the slider does not clearly pay for
  itself, the honest move is to drop the idea rather than ship the other four controls.

## 15. Open questions

These change the design and are yours to decide:

1. **`UnrestPart` as a separate attribute, or reuse `UnrestRole` scoped to the subtree?** The
   proposal argues separate; reusing is one fewer concept but couples control resolution to
   global role uniqueness.
2. **Should a control root also be adoptable as a plain element?** Allowing both means
   `UnrestCommand` and `UnrestControl` could sit on one instance with unclear precedence.
3. **Orientation inferred from the track, or always explicit?** Inference makes a redesign
   work untouched; explicitness never surprises.
4. **Dispatch throttled during a drag, or only on release?** Throttled is more responsive for
   shared state; release-only is cheaper and never partially applies.
5. **Is `Slider` the right first control**, or is `Toggle` a cheaper way to prove the model?

## 16. Status

Proposal. No code has been written and none should be until you say so.
