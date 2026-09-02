--!strict
--[[
    Unrest / Adapters / Types

    Types for the adoption layer: adapters, managed elements, and the query engine.

    The framework builds no UI. Every element it touches was made by hand in Studio, so an
    *adapter* is how the framework learns what a given Roblox class can do -- which events
    exist on it, and which properties are safe to write from a channel. Adapters compose
    along the class hierarchy (`GuiObject` -> `GuiButton` -> `TextButton`), so a new class
    usually needs only the handful of things it adds.

    Owned by the adoption layer. Additive changes are fine; do not rename what is here.
]]

local Primitives = require(script.Parent.Parent.Primitives)

type Signal<T...> = Primitives.Signal<T...>

--------------------------------------------------------------------------------
-- Handlers
--------------------------------------------------------------------------------

--[[
    Every handler receives the element it fired for, and a value. `value` is only meaningful
    for the value-carrying handlers (`Changed`, `Submit`); it is nil everywhere else,
    including in `QueryHandle:Each`. A one-parameter function is assignable here, so
    `function(element) end` is fine.

    A handler never sees whatever argument the underlying Roblox event carried unless that
    handler's entry below says so. `ClickDetector.MouseClick` is handed a Player and
    `ProximityPrompt.PromptShown` an input type; both are dropped on the floor, because
    adoption is client-only and the player is therefore always this one.
]]
export type ElementHandler = (element: Instance, value: any) -> ()

--[[
    The binding matrix: the twelve verbs the framework speaks, whatever class is underneath.
    Ten of them are events some adapter declares; `Added` and `Removed` describe the *query's*
    lifecycle rather than the element's, so every instance has them -- including a Folder or a
    Part with no adapter at all.

    A handler is only accepted for an element whose adapter declares the matching event. What
    happens when it is not depends on who asked, and the difference is deliberate:

      * **Code raises.** `Query:Bind({ Submit = ... })` against a Frame throws. Code that
        binds a handler its element cannot support is a bug, and it should stop at the line
        that wrote it rather than become a button that quietly never works.
      * **Attributes warn.** The same mistake made in Studio -- `UnrestCommand` on a TextLabel
        -- warns, names the element, names the fix, and leaves the rest of the screen up. An
        attribute is data, usually typed by somebody who is not watching the output window,
        and taking a whole menu down over one of them is the worse outcome.

    Both paths run through `Adapters.bind` and print the same sentence at two severities. Note
    which side of that line you are on: exactly one handler is reachable from an attribute at
    all -- `UnrestCommand` wires `Active` -- so every other name here is code-only and
    therefore always raises.

    Three traps cut across the whole table and are worth reading before the per-handler notes.

    1. **Every enter/leave pair can lose its leave.** `Press`/`Release`, `Hover`/`Unhover` and
       `Focus`/`Blur` all look symmetric and none of them is guaranteed to be. The worst case
       is `Press`/`Release` on a GuiObject: `InputEnded` only fires while the pointer is still
       over that instance, so dragging off a button while held fires `Press` and never
       `Release`. A `Visible = false` written by a channel, an element released mid-gesture
       (untagged, `UnrestIgnore` ticked, reparented out of the query), and a `:Destroy()` all
       do the same thing to the pair. So never store "is pressed" or "is hovered" as state a
       later event has to clear: either drive the visual from the enter event alone, or reset
       it in `Removed`, which is the one departure the framework does guarantee.

    2. **`Changed` is synthesised, never written by hand.** The registry manufactures it from
       the adapter's `ValueProperty`, so a class has `Changed` exactly when it has one obvious
       value. `TextLabel`/`TextButton`/`TextBox` (Text), `ImageLabel`/`ImageButton` (Image),
       `ScrollingFrame` (CanvasPosition), `CanvasGroup` (GroupTransparency), `VideoFrame`
       (Video), `LayerCollector` and its three subclasses (Enabled), `UICorner` (CornerRadius)
       and `UIScale` (Scale) have one. `Frame`, `ViewportFrame`, `UIListLayout`,
       `ClickDetector` and `ProximityPrompt` deliberately do not, and binding `Changed` to one
       of them raises. `ValueProperty` flattens down the `Extends` chain like everything else,
       which is why `ScreenGui` reports `Enabled` without saying so itself.

    3. **`Active` means two unrelated things in this codebase.** It is a handler name on
       `GuiButton`, and it is a bindable *property* name on `GuiBase2d`. So `Supports(x,
       "Active")` and `CanBind(x, "Active")` answer different questions from the same string,
       and a TextLabel answers false to the first and true to the second. Worse, the two
       interact: `Activated` does not fire while the property is false, so a channel bound to
       `Active` can silence the `Active` handler while `Press` and `Release` keep firing.

    `docs/UI-BINDING.md` section 3 carries the full handler-by-class matrix. It lives there
    rather than here because it is five columns wide and only makes sense next to the adapter
    coverage tables it depends on; these comments answer "what does this one name do", the
    document answers "which of the twelve does my class have".
]]
export type Handlers = {
    --[[
        Primary activation -- the commit. `GuiButton.Activated` (so TextButton and
        ImageButton), `ClickDetector.MouseClick`, `ProximityPrompt.Triggered`. `value` is nil;
        the Player the two 3D events carry is dropped.

        `Activated` rather than `MouseButton1Click` on purpose: it already folds mouse, touch
        and gamepad into one event, and already respects `Modal` and the `Active` property --
        which is also the trap, since both of those can silence it without disconnecting
        anything. This is the only handler an attribute can ask for (`UnrestCommand`), and so
        the only one whose failure is ever a warning rather than an error.
    ]]
    Active: ElementHandler?,
    --[[
        Secondary activation: `GuiButton.MouseButton2Click`, `ClickDetector.RightMouseClick`.
        `value` is nil.

        Mouse-only, on every class that has it. It simply never fires on touch or gamepad,
        which is the honest behaviour rather than a gap -- so a right-click must never be the
        only route to an action. A `ProximityPrompt` has no second button at all: binding
        `Secondary` to one raises.
    ]]
    Secondary: ElementHandler?,
    --[[
        Pointer down. On any `GuiObject`, `InputBegan` filtered to MouseButton1 and Touch --
        keyboard and gamepad input routed at the element is deliberately not a press. On a
        `ProximityPrompt`, `PromptButtonHoldBegan`. `value` is nil.

        Two traps. `Press` reaches every GuiObject, Frames and TextLabels included, because it
        is declared on `GuiObject` -- so it binds happily to things a player has no reason to
        press. And on a prompt the hold events only exist when `HoldDuration > 0`: with the
        default of zero, `Press` and `Release` never fire once, while `Active` fires normally.
        `HoldDuration` is bindable, so a channel can turn this pair off from the server.
    ]]
    Press: ElementHandler?,
    --[[
        Pointer up: `GuiObject.InputEnded` under the same filter, or
        `ProximityPrompt.PromptButtonHoldEnded`. `value` is nil.

        **`GuiObject.InputEnded` only fires while the pointer is still over that instance.**
        Press a button, drag off it, let go -- `Press` fired, `Release` never will. Anything
        built as a drag on top of this pair (a slider, a held-to-charge action, a "pressed"
        tint) gets a state that is stuck until the next `Press`. There is no fix inside the
        adapter: the framework will not connect `UserInputService` on the element's behalf,
        because a global input listener is not something a tag should silently buy you. Reset
        in `Removed`, or key the visual off `Press` and a timer.
    ]]
    Release: ElementHandler?,
    --[[
        Pointer or attention arrives. `GuiObject.MouseEnter`, `ClickDetector.MouseHoverEnter`,
        `ProximityPrompt.PromptShown`. `value` is nil.

        The three are not the same event wearing one name. `MouseEnter` is mouse-only, so it
        never fires on a touch device -- a hover-only affordance is invisible on mobile.
        `MouseHoverEnter` fires for a 3D part under the cursor and hands Roblox a Player the
        binder discards. `PromptShown` is not a pointer event at all: it fires when the prompt
        becomes visible, which is proximity and line of sight, and it re-fires every time the
        player walks back into range. Reaching for `Hover` to mean "is being pointed at" is
        right for the first two and wrong for the third.
    ]]
    Hover: ElementHandler?,
    --[[
        The counterpart: `GuiObject.MouseLeave`, `ClickDetector.MouseHoverLeave`,
        `ProximityPrompt.PromptHidden`. `value` is nil.

        Not guaranteed, in the same way `Release` is not. `MouseLeave` fires when the pointer
        moves off; it does not fire when the element is hidden, destroyed or moved out from
        under a stationary cursor. `Visible` is a bindable property, so a channel that hides a
        hovered element leaves the hover state on.
    ]]
    Unhover: ElementHandler?,
    --[[
        Keyboard focus gained: `TextBox.Focused`. `TextBox` is the only class in the framework
        with any of Focus / Blur / Submit, so binding one anywhere else raises. `value` is nil.
    ]]
    Focus: ElementHandler?,
    --[[
        Keyboard focus lost: `TextBox.FocusLost`, unconditionally. `value` is nil.

        Every commit is also a blur, so pressing Enter fires `Blur` *and* `Submit` from two
        separate connections to the same signal. Their relative order is not defined -- the
        connections are made while iterating a hash table -- so neither may assume the other
        has run. Use `Blur` for "the box is no longer being edited" and `Submit` for the value.
    ]]
    Blur: ElementHandler?,
    --[[
        A committed value: `TextBox.FocusLost` with `enterPressed` true. `value` is the
        TextBox's `Text` at that moment, a string.

        Clicking away is not a commit, and neither is Escape -- both fire `Blur` alone. This is
        one of the two handlers whose `value` is real.
    ]]
    Submit: ElementHandler?,
    --[[
        The adapter's `ValueProperty` changed. `value` is that property's current value, typed
        by the property: a string for Text, a Vector2 for CanvasPosition, a number for
        GroupTransparency, a boolean for a LayerCollector's Enabled.

        Read the current value rather than the changed one -- Roblox's
        `GetPropertyChangedSignal` carries no payload, so the binder reads the property back
        when it fires. Two writes in the same frame can therefore report the later value
        twice, and there is never a previous value to compare against.

        It also fires for writes the framework itself makes. `UnrestBind` defaults to the very
        property `Changed` watches, so an element that both follows a channel and handles
        `Changed` will hear its own repaint; a `Changed` that dispatches back into the channel
        is a loop. And on a TextBox it fires per keystroke, which is what `Submit` exists to
        avoid.
    ]]
    Changed: ElementHandler?,
    --[[
        The element started matching the descriptor. `value` is nil. Not an adapter event: it
        is the query's own lifecycle, supported by every instance including those with no
        adapter, so a query carrying only `Added`/`Removed` can select a Folder.

        It fires for elements that already match when the query is created -- synchronously,
        inside the `Unrest:Query` call, before the handle is returned. A handler that reaches
        for the handle it is being created by will find a nil upvalue.

        `QueryHandle:Bind` is the asymmetry to watch: merging an `Added` in later rebinds every
        element but fires `Added` for none of them, because they had already arrived. Pass
        `Added` in the initial `Query` call when you need it for the existing set.
    ]]
    Added: ElementHandler?,
    --[[
        The element stopped matching: untagged, `UnrestIgnore` ticked, renamed, reparented
        away, destroyed, or the query itself destroyed. `value` is nil, and like `Added` this
        is query lifecycle rather than an adapter event.

        Exactly once per departure, and it is the one guarantee in this table -- which is why
        it is the right place to undo anything an interaction handler left behind. It runs
        *after* the element's event connections are torn down, so the element is already inert
        by then, and when the cause was `Destroying` the instance is on its way out: do the
        cleanup now rather than deferring it to a frame where there is nothing to clean.
    ]]
    Removed: ElementHandler?,
}

--------------------------------------------------------------------------------
-- Adapters
--------------------------------------------------------------------------------

--[[
    Connects one handler name to one Roblox event on one class. Returning nil means the
    element does not actually support it despite its class (rare, but real: a TextButton
    inside a disabled ScreenGui still connects, whereas some classes gate events). A binder
    that returns a connection has it parked in the element's maid, so nothing here has to
    think about teardown.

    The binder also decides what a handler's `value` is, and every built-in one but two passes
    nil -- deliberately, since forwarding whatever argument the Roblox event happened to carry
    would make `value` mean a different thing per class. `TextBox` forwards the committed text
    to `Submit`, and the synthesised `Changed` forwards the watched property. `ClickDetector`
    and `ProximityPrompt` are handed a Player and drop it: adoption is client-only, so the
    answer would always be the same player.
]]
export type EventBinder = (element: Instance, invoke: (value: any) -> ()) -> RBXScriptConnection?

--- What an adapter author writes.
export type Adapter = {
    --- The Roblox ClassName this adapter teaches, e.g. "GuiButton" or "TextBox".
    ClassName: string,
    --- Base adapter this one composes on top of. Usually the superclass.
    Extends: string?,
    --- Handler name -> how to connect it. Merged with the `Extends` chain, derived wins. An
    --- adapter can therefore replace a binder it inherited, but never remove one: a subclass
    --- of `GuiObject` gets `Press` whether or not pressing it means anything.
    Events: { [string]: EventBinder }?,
    --- Property names a designer may target with `UnrestBind`. An allowlist, on purpose:
    --- a channel value must never be able to write an arbitrary property.
    Bindable: { [string]: boolean }?,
    --[[
        The property a `Changed` handler watches, what `UnrestBind` defaults to, and what
        `Submit` reports. Declaring it is what *gives* a class `Changed` at all: the registry
        synthesises the binder, so the two can never drift apart. It flattens down the
        `Extends` chain like everything else and cannot be un-declared, so a class with no
        obvious value must inherit from one that has none either -- which is why `Frame`
        extends `GuiObject` and stays silent rather than picking a property to mean "the" one.
    ]]
    ValueProperty: string?,
}

--- An adapter after its `Extends` chain has been flattened.
export type ResolvedAdapter = {
    ClassName: string,
    --- Most specific first, e.g. { "TextButton", "GuiButton", "GuiObject" }.
    Chain: { string },
    Events: { [string]: EventBinder },
    Bindable: { [string]: boolean },
    ValueProperty: string?,
}

export type AdapterRegistry = {
    AdapterAdded: Signal<Adapter>,
    --- Registers an adapter, replacing any adapter for the same ClassName.
    Register: (self: AdapterRegistry, adapter: Adapter) -> Adapter,
    --- The most specific registered adapter this instance `:IsA()`, flattened. Cached.
    Resolve: (self: AdapterRegistry, instance: Instance) -> ResolvedAdapter?,
    --[[
        Whether this instance's adapter can bind that handler name. Always true for `Added`
        and `Removed`, which are the query's lifecycle and belong to every instance -- the
        adapter is not even resolved for them.

        Watch `"Active"` here. It is both a handler name and a bindable property name, so
        `Supports(x, "Active")` and `CanBind(x, "Active")` are two different questions wearing
        one string: a TextLabel says no to the first and yes to the second.
    ]]
    Supports: (self: AdapterRegistry, instance: Instance, handler: string) -> boolean,
    --- Whether a channel value may be written into that property on this instance. See the
    --- note on `Supports` about `"Active"`, which both functions accept and disagree over.
    CanBind: (self: AdapterRegistry, instance: Instance, property: string) -> boolean,
    --[[
        One sentence naming the adapter this instance resolves to and everything it can do.
        Exists so the "you cannot bind that here" error can be actionable in one line, and
        so that message is written once rather than at every call site that raises it.
    ]]
    Describe: (self: AdapterRegistry, instance: Instance) -> string,
    List: (self: AdapterRegistry) -> { string },
}

--------------------------------------------------------------------------------
-- Managed elements
--------------------------------------------------------------------------------

--[[
    Which of the three resolution layers supplied one attribute value.

      * `Own`       -- set on the element itself.
      * `Preset`    -- expanded from the bundle its `UnrestPreset` names.
      * `Inherited` -- read off the nearest ancestor that sets an inheritable attribute.

    Most specific wins: `Own` beats `Preset` beats `Inherited`. A preset is a default and an
    ancestor is a fallback; neither can override what the designer typed on the element.
]]
export type AttributeOrigin = "Own" | "Preset" | "Inherited"

--- One entry of `ManagedElement.Sources`: which layer won, and where the value came from.
export type AttributeSource = {
    Origin: AttributeOrigin,
    --- The preset that supplied the value, when `Origin` is `"Preset"`.
    Preset: string?,
    --- The ancestor that supplied it, when `Origin` is `"Inherited"`.
    Ancestor: Instance?,
    --- One phrase naming the source, e.g. `set here`, `from preset "PrimaryAction"`,
    --- `inherited from Menu (ScreenGui)`.
    Text: string,
}

--- Everything the framework knows about one adopted instance.
export type ManagedElement = {
    Instance: Instance,
    Adapter: ResolvedAdapter,
    --- `UnrestRole` attribute, falling back to `Instance.Name`. Never inherited: a role is
    --- this element's identity, not its context.
    Role: string,
    --- Resolved `UnrestGroup`: the element's own, or the nearest ancestor's.
    Group: string?,
    --[[
        The element's `Unrest*` attributes after resolution -- its own over its preset's
        over the nearest ancestor's inheritable ones -- refreshed whenever any of the three
        changes. The rest of the framework reads this and nothing else.
    ]]
    Attributes: { [string]: any },
    --- Name of the preset that expanded into `Attributes`, when one applied and resolved.
    --- An `UnrestPreset` naming a preset nobody declared warns and leaves this nil.
    Preset: string?,
    --- Provenance for every key of `Attributes`, so "who set this?" has an answer.
    Sources: { [string]: AttributeSource },
    Released: Signal<ManagedElement>,
}

--[[
    Owns adoption. Watches the framework tag, resolves an adapter per element, wires the
    declarative attributes, and answers queries.

    Client-only by design. Server-side code must never trust a UI event: the authority is
    the command contract, not the button that dispatched it.
]]
export type ElementManager = {
    ManagedAdded: Signal<ManagedElement>,
    ManagedRemoved: Signal<ManagedElement>,
    --- Begins watching the tag and adopts what already exists. Idempotent.
    Start: (self: ElementManager) -> (),
    --- Adopts one instance directly, tag or no tag. Returns nil if no adapter matches.
    Adopt: (self: ElementManager, instance: Instance) -> ManagedElement?,
    Release: (self: ElementManager, instance: Instance) -> (),
    Get: (self: ElementManager, instance: Instance) -> ManagedElement?,
    All: (self: ElementManager) -> { ManagedElement },
    Query: (self: ElementManager, descriptor: Descriptor, handlers: Handlers?) -> QueryHandle,
    Destroy: (self: ElementManager) -> (),
}

--------------------------------------------------------------------------------
-- Query
--------------------------------------------------------------------------------

--[[
    The whiteboard's selector:

        Unrest:Query({ Tag = "Unrest", Selector = "TextButton", Name = "ToggleMenu" }, { ... })

    A descriptor needs at least one of Tag / Selector / Name / Role / Group, and needs an
    `Ancestor` when it has no `Tag`.
]]
export type Descriptor = {
    --- CollectionService tag. Drives live binding via GetInstanceAdded/RemovedSignal.
    Tag: string?,
    --- ClassName tested with `:IsA()` -- the board's `is:A("Button")`.
    Selector: string?,
    --- Exact `Instance.Name`. Re-evaluated live when an element is renamed.
    Name: string?,
    --- `UnrestRole` attribute. Prefer this over `Name`: designers rename things.
    Role: string?,
    --- `UnrestGroup` attribute.
    Group: string?,
    --- Search root. Required when no `Tag` is supplied.
    Ancestor: Instance?,
    --- Search descendants of `Ancestor` rather than only its children. Defaults to true.
    Recursive: boolean?,
}

--- A descriptor after validation and default filling.
export type CompiledSelector = {
    Tag: string?,
    Selector: string?,
    Name: string?,
    Role: string?,
    Group: string?,
    Ancestor: Instance?,
    Recursive: boolean,
    --- Human-readable form used in error messages, e.g. `{Tag = "Unrest", is:A("TextButton")}`.
    Text: string,
}

--- A live result set, kept in sync with CollectionService and the element's attributes.
export type QueryHandle = {
    Selector: CompiledSelector,
    ElementAdded: Signal<Instance>,
    ElementRemoved: Signal<Instance>,
    Elements: (self: QueryHandle) -> { Instance },
    Count: (self: QueryHandle) -> number,
    --- Visits the current elements. Chainable.
    Each: (self: QueryHandle, visitor: ElementHandler) -> QueryHandle,
    --- Merges more handlers in and rebinds every element. Chainable.
    Bind: (self: QueryHandle, handlers: Handlers) -> QueryHandle,
    Destroy: (self: QueryHandle) -> (),
}

return table.freeze({})
