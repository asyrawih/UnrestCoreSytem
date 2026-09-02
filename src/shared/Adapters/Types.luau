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
    Every handler receives the element it fired for, and a value. `value` is only
    meaningful for the value-carrying handlers (`Changed`, `Submit`); it is nil elsewhere.
    A one-parameter function is assignable here, so `function(element) end` is fine.
]]
export type ElementHandler = (element: Instance, value: any) -> ()

--[[
    The binding matrix. A handler is only accepted for an element whose adapter declares
    the matching event -- binding `Submit` to a Frame is a loud error, not a no-op.
]]
export type Handlers = {
    --- Primary activation: Activated / MouseButton1Click / MouseClick / Triggered.
    Active: ElementHandler?,
    --- Secondary activation: MouseButton2Click, or the class equivalent.
    Secondary: ElementHandler?,
    --- Pointer down / up on the element.
    Press: ElementHandler?,
    Release: ElementHandler?,
    --- Pointer entered / left: MouseEnter, MouseLeave, MouseHoverEnter, MouseHoverLeave.
    Hover: ElementHandler?,
    Unhover: ElementHandler?,
    --- Keyboard/gamepad focus gained or lost (TextBox).
    Focus: ElementHandler?,
    Blur: ElementHandler?,
    --- Committed value: TextBox FocusLost with enter pressed.
    Submit: ElementHandler?,
    --- The element's value property changed (Text, CanvasPosition, Value, ...).
    Changed: ElementHandler?,
    --- The element started matching the descriptor.
    Added: ElementHandler?,
    --- The element stopped matching it: untagged, renamed, reparented away, or destroyed.
    Removed: ElementHandler?,
}

--------------------------------------------------------------------------------
-- Adapters
--------------------------------------------------------------------------------

--[[
    Connects one handler name to one Roblox event on one class. Returning nil means the
    element does not actually support it despite its class (rare, but real: a TextButton
    inside a disabled ScreenGui still connects, whereas some classes gate events).
]]
export type EventBinder = (element: Instance, invoke: (value: any) -> ()) -> RBXScriptConnection?

--- What an adapter author writes.
export type Adapter = {
    --- The Roblox ClassName this adapter teaches, e.g. "GuiButton" or "TextBox".
    ClassName: string,
    --- Base adapter this one composes on top of. Usually the superclass.
    Extends: string?,
    --- Handler name -> how to connect it. Merged with the `Extends` chain.
    Events: { [string]: EventBinder }?,
    --- Property names a designer may target with `UnrestBind`. An allowlist, on purpose:
    --- a channel value must never be able to write an arbitrary property.
    Bindable: { [string]: boolean }?,
    --- The property a `Changed` handler watches, and what `Submit` reports.
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
    --- Whether this instance's adapter can bind that handler name.
    Supports: (self: AdapterRegistry, instance: Instance, handler: string) -> boolean,
    --- Whether a channel value may be written into that property on this instance.
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
    --- One phrase naming the source, e.g. `set here`, `from preset "MusicToggle"`,
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
