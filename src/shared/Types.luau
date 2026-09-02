--!strict
--[[
    Unrest / Types

    Single source of truth for every public type in the framework.

    This module intentionally has ZERO requires: every layer (Core, Bridge, UI, and user
    code) may depend on it without ever creating a require cycle. If a type is part of the
    public API surface, it lives here and nowhere else.
]]

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

export type RuntimeContext = "Server" | "Client"

--- A plain teardown function.
export type Cleanup = () -> ()

--- The framework's own connection object (returned by `Signal:Connect`).
export type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

--- Anything exposing `:Destroy()`.
export type Destroyable = { Destroy: (self: any) -> () }

--- Anything exposing `:Disconnect()`.
export type Disconnectable = { Disconnect: (self: any) -> () }

--- Every value a `Maid` knows how to clean up.
export type MaidTask = Instance | RBXScriptConnection | thread | Cleanup | Destroyable | Disconnectable

--- Deterministic, ordered cleanup container. Tasks are cleaned in reverse insertion order.
export type Maid = {
    --- Tracks `item`. When `key` is given the previous task stored under that key is cleaned first.
    Add: (self: Maid, item: MaidTask, key: string?) -> MaidTask,
    --- Cleans and forgets the task stored under `key`.
    Remove: (self: Maid, key: string) -> (),
    --- Cleans every tracked task but keeps the maid usable.
    Clean: (self: Maid) -> (),
    --- Cleans every tracked task and refuses further work (later `Add` calls clean immediately).
    Destroy: (self: Maid) -> (),
    IsDestroyed: (self: Maid) -> boolean,
}

--- Minimal, dependency-free signal.
export type Signal<T...> = {
    Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
    Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
    Wait: (self: Signal<T...>) -> T...,
    Fire: (self: Signal<T...>, T...) -> (),
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}

--------------------------------------------------------------------------------
-- Query: descriptors, handlers, handles
--------------------------------------------------------------------------------

--[[
    The jQuery-like selector from the whiteboard:

        Unrest:Query({ Tag = "Unrest", Selector = "TextButton", Name = "ToggleMenu" }, { ... })

    Every field is optional on its own, but a descriptor must carry at least one of
    `Tag` / `Selector` / `Name`, and must carry an `Ancestor` when it has no `Tag`.
]]
export type Descriptor = {
    --- CollectionService tag. Drives live binding via GetInstanceAdded/RemovedSignal.
    Tag: string?,
    --- ClassName tested with `:IsA()` -- the board's `is:A("Button")`.
    Selector: string?,
    --- Exact `Instance.Name`. Re-evaluated live when an element is renamed.
    Name: string?,
    --- Search root. Required when no `Tag` is supplied.
    Ancestor: Instance?,
    --- Search descendants of `Ancestor` rather than only its children. Defaults to `true`.
    Recursive: boolean?,
}

--- A descriptor after `Resolver` validation and default filling.
export type CompiledSelector = {
    Tag: string?,
    Selector: string?,
    Name: string?,
    Ancestor: Instance?,
    Recursive: boolean,
    --- Human readable form used in error messages, e.g. `{Tag = "Unrest", is:A("TextButton")}`.
    Text: string,
}

export type ElementHandler = (element: Instance) -> ()

--[[
    Handler table. Keys are validated by `Resolver` -- an unknown or wrong-typed key throws
    with the offending key named. See `docs/ARCHITECTURE.md` for the binding matrix.
]]
export type Handlers = {
    --- Activated (GuiButton) / MouseClick (ClickDetector) / Triggered (ProximityPrompt).
    Active: ElementHandler?,
    --- MouseEnter (GuiObject) / MouseHoverEnter (ClickDetector).
    Hover: ElementHandler?,
    --- MouseLeave (GuiObject) / MouseHoverLeave (ClickDetector).
    Unhover: ElementHandler?,
    --- Fired when an instance starts matching the descriptor.
    Added: ElementHandler?,
    --- Fired when an instance stops matching the descriptor (untagged, renamed, destroyed).
    Removed: ElementHandler?,
}

--- Live result set. Stays in sync with CollectionService / the ancestor subtree.
export type QueryHandle = {
    Selector: CompiledSelector,
    ElementAdded: Signal<Instance>,
    ElementRemoved: Signal<Instance>,
    --- Snapshot copy of the currently matching elements.
    Elements: (self: QueryHandle) -> { Instance },
    Count: (self: QueryHandle) -> number,
    --- Visits the current elements. Chainable.
    Each: (self: QueryHandle, visitor: ElementHandler) -> QueryHandle,
    --- Merges more handlers in and rebinds every element. Chainable.
    Bind: (self: QueryHandle, handlers: Handlers) -> QueryHandle,
    Destroy: (self: QueryHandle) -> (),
}

--------------------------------------------------------------------------------
-- Core: systems and registry
--------------------------------------------------------------------------------

--[[
    Lifecycle contract:
      1. every system's `Init(unrest)` runs, in dependency order;
      2. every system's `Start()` runs, in the same order;
      3. `Destroy()` runs in reverse order on shutdown.
    The teardown hook is `Destroy`, not `Stop`, so it never collides with a domain verb
    (`MusicSystem:Stop()` stops the music; `MusicSystem:Destroy()` retires the system).
    A system may hold any extra fields; only these are inspected by the registry.
]]
export type System = {
    Name: string,
    Dependencies: { string }?,
    Init: ((self: any, unrest: Unrest) -> ())?,
    Start: ((self: any) -> ())?,
    Destroy: ((self: any) -> ())?,
}

export type Core = {
    SystemAdded: Signal<System>,
    --- Registers a system. After startup the system is booted immediately.
    Register: (self: Core, definition: System) -> System,
    Get: (self: Core, name: string) -> System?,
    --- Like `Get` but throws a message listing the registered systems.
    Expect: (self: Core, name: string) -> System,
    Has: (self: Core, name: string) -> boolean,
    --- Registered system names in dependency order.
    List: (self: Core) -> { string },
    Start: (self: Core, unrest: Unrest) -> (),
    Stop: (self: Core) -> (),
    IsStarted: (self: Core) -> boolean,
}

--------------------------------------------------------------------------------
-- Built-in system shapes
--------------------------------------------------------------------------------

export type Track = {
    Name: string,
    SoundId: string,
    Volume: number?,
    Looped: boolean?,
}

export type MusicSystem = System & {
    NowPlayingChanged: Signal<string?>,
    AddTrack: (self: MusicSystem, track: Track) -> (),
    Play: (self: MusicSystem, name: string) -> boolean,
    Stop: (self: MusicSystem) -> (),
    SetVolume: (self: MusicSystem, volume: number) -> (),
    GetCurrent: (self: MusicSystem) -> string?,
    List: (self: MusicSystem) -> { string },
}

export type AvatarContext = System & {
    CharacterAdded: Signal<Player, Model>,
    CharacterRemoving: Signal<Player, Model>,
    --- On the client `player` defaults to `Players.LocalPlayer`; on the server it is required.
    Resolve: (self: AvatarContext, player: Player?) -> Player?,
    GetCharacter: (self: AvatarContext, player: Player?) -> Model?,
    GetHumanoid: (self: AvatarContext, player: Player?) -> Humanoid?,
    GetAnimator: (self: AvatarContext, player: Player?) -> Animator?,
}

export type DanceSystem = System & {
    DanceChanged: Signal<Player, string?>,
    AddDance: (self: DanceSystem, name: string, animationId: string) -> (),
    Play: (self: DanceSystem, name: string, player: Player?) -> boolean,
    Stop: (self: DanceSystem, player: Player?) -> (),
    GetCurrent: (self: DanceSystem, player: Player?) -> string?,
    List: (self: DanceSystem) -> { string },
}

export type PluginExtended = System & {
    PluginAdded: Signal<System>,
    --- Registers a third-party system into Core at runtime.
    Register: (self: PluginExtended, definition: System) -> System,
    --- Requires every ModuleScript child of `container` and registers what they return.
    LoadFromFolder: (self: PluginExtended, container: Instance) -> { System },
    List: (self: PluginExtended) -> { string },
}

--------------------------------------------------------------------------------
-- Bridge: the controller
--------------------------------------------------------------------------------

--[[
    The only channel between Core and UI.
      * Core -> UI  : `Publish` / `Subscribe` (retained: subscribers get the last value).
      * UI   -> Core: `Dispatch` / `OnCommand`.
      * UI element access: `Query`.
    The Bridge is process-local; it does not cross the client/server boundary.
]]
export type Bridge = {
    Query: (self: Bridge, descriptor: Descriptor, handlers: Handlers?) -> QueryHandle,
    Publish: (self: Bridge, channel: string, value: any) -> (),
    Subscribe: (self: Bridge, channel: string, handler: (value: any) -> ()) -> Connection,
    --- Last published value on `channel`, or nil.
    Peek: (self: Bridge, channel: string) -> any,
    Dispatch: (self: Bridge, command: string, payload: any) -> (),
    OnCommand: (self: Bridge, command: string, handler: (payload: any) -> ()) -> Connection,
    Destroy: (self: Bridge) -> (),
}

--------------------------------------------------------------------------------
-- UI: the view
--------------------------------------------------------------------------------

export type Props = { [string]: any }

--- What `Component.Create` returns and what `UI:Mount` hands back.
export type ComponentHandle = {
    Name: string,
    Instance: GuiObject,
    Props: Props,
    Destroyed: Signal<ComponentHandle>,
    Update: (self: ComponentHandle, props: Props) -> ComponentHandle,
    Destroy: (self: ComponentHandle) -> (),
}

export type Component = {
    Name: string,
    Create: (props: Props, bridge: Bridge) -> ComponentHandle,
}

export type UI = {
    ComponentMounted: Signal<ComponentHandle>,
    Register: (self: UI, component: Component) -> Component,
    Get: (self: UI, name: string) -> Component?,
    Mount: (self: UI, name: string, props: Props, parent: Instance) -> ComponentHandle,
    List: (self: UI) -> { string },
    Destroy: (self: UI) -> (),
}

--- Typed props for the `DxChipsX` reference component.
export type ChipProps = {
    --- Instance.Name given to the chip's root button. Defaults to "DxChipsX".
    Name: string?,
    Text: string?,
    Color: Color3?,
    TextColor: Color3?,
    --- Extra CollectionService tags. The framework tag is always applied.
    Tags: { string }?,
    --- Shows the trailing dismiss button.
    Removable: boolean?,
    Selected: boolean?,
    OnActivated: ((handle: ComponentHandle) -> ())?,
    OnRemoved: ((handle: ComponentHandle) -> ())?,
}

--------------------------------------------------------------------------------
-- The singleton
--------------------------------------------------------------------------------

export type Unrest = {
    Version: string,
    --- "Server" or "Client", decided by RunService.
    Context: RuntimeContext,
    --- Default CollectionService tag applied to framework-built UI.
    Tag: string,
    Core: Core,
    Bridge: Bridge,
    UI: UI,
    --- Boots every registered system (Init pass, then Start pass). Idempotent-guarded.
    Start: (self: Unrest) -> Unrest,
    Stop: (self: Unrest) -> (),
    IsStarted: (self: Unrest) -> boolean,
    --- Registers a Core system. Shorthand for `Unrest.Core:Register`.
    Register: (self: Unrest, definition: System) -> System,
    --- Throws if the system is not registered. Cast the result to its exported type.
    Get: (self: Unrest, name: string) -> System,
    --- Shorthand for `Unrest.Bridge:Query`.
    Query: (self: Unrest, descriptor: Descriptor, handlers: Handlers?) -> QueryHandle,
    --- Shorthand for `Unrest.UI:Mount`.
    Mount: (self: Unrest, component: string, props: Props, parent: Instance) -> ComponentHandle,
}

-- Type-only module: the returned table is intentionally empty.
return table.freeze({})
