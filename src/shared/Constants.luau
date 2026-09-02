--!strict
--[[
    Unrest / Constants

    Stringly-typed values more than one layer needs, and nothing a game names. An attribute
    or remote name is never spelled twice here, so a typo is a nil index rather than a silent
    no-op.

    Command and channel names are deliberately absent. They belong to the game, which
    registers them with `Contracts:Declare` and keeps its own names wherever it likes; the
    framework only ever handles them as opaque strings.
]]

local Constants = {
    Version = "0.2.0",

    --[[
        The CollectionService tag that hands an instance to the framework.

        UI is built in Studio, by hand. The framework creates none of it. Tagging an
        instance `Unrest` is the whole opt-in: from that moment it is adopted, an adapter is
        resolved for its ClassName, its `Unrest*` attributes are wired, and it becomes
        visible to `Unrest:Query`. Removing the tag releases it cleanly.

        The tag cascades. Tagging a Frame manages that Frame *and* every `GuiObject` under
        it, so a screen is opted in by tagging its container once rather than by tagging
        forty buttons. Tag a single button and you get a single button, because a button
        rarely has GuiObject children -- the same rule reads both ways.

        Non-visual children are not swept up: a `UIListLayout` or `UICorner` under a tagged
        Frame is left alone unless you tag it yourself. They carry no events and exist to
        lay other things out, so adopting them would be noise.

        `UnrestIgnore = true` on any instance opts it and its descendants back out.
    ]]
    Tag = "Unrest",

    --[[
        Attributes a designer sets in Studio to wire an element with no code at all.
        Every one is optional; an element with only the tag is still adopted and queryable.
    ]]
    Attributes = table.freeze({
        --- Logical name used by queries. Defaults to `Instance.Name`. Lets designers rename
        --- freely without breaking code that selects the element.
        Role = "UnrestRole",
        --- Free-form grouping ("MainMenu", "Shop"), selectable via `Descriptor.Group`.
        Group = "UnrestGroup",
        --- Command dispatched when the element is activated. Subject to the same contract
        --- checks as a code-driven dispatch -- an attribute is not a privilege escalation.
        Command = "UnrestCommand",
        --- Payload sent with `Command`. Attributes are primitives only, by Roblox's design.
        Payload = "UnrestPayload",
        --- Channel this element subscribes to for its displayed value.
        Channel = "UnrestChannel",
        --- Property the channel value is written into ("Text", "Visible", ...). Must be
        --- declared `Bindable` by the element's adapter.
        Bind = "UnrestBind",
        --- Format string applied to the channel value, e.g. "Status: {value}".
        Format = "UnrestFormat",
        --- Seconds of client-side debounce between activations. Advisory only: the server
        --- rate limit is the real one.
        Cooldown = "UnrestCooldown",
        --- Names an entry in `Presets.luau`, which expands into several of the attributes
        --- above. One attribute instead of five, defined once and reused.
        Preset = "UnrestPreset",
        --[[
            Opts an instance and everything under it back out of a cascading tag. The escape
            hatch for the one decorative subtree inside an otherwise managed screen; set it
            to `true`.
        ]]
        Ignore = "UnrestIgnore",
    }),

    --[[
        Attributes a descendant inherits from an ancestor when it does not set its own.

        The rule is inherit context, never intent. `UnrestGroup` says which screen an element
        belongs to and every element on that screen shares the answer, so it belongs on the
        ScreenGui once. `UnrestCommand` says what this one button does, and inheriting it
        would silently arm every descendant of a panel with the same command -- so it is not
        inheritable, and neither is anything else that names a specific behaviour.

        Precedence, most specific first:
            the element's own attribute  >  its preset  >  the nearest ancestor's
    ]]
    Inheritable = table.freeze({
        UnrestGroup = true,
        UnrestCooldown = true,
        UnrestPreset = true,
    }),

    --- Names of the replicated objects. The server creates them; the client waits for them.
    Remotes = table.freeze({
        Folder = "UnrestRemotes",
        --- Client -> server, fire and forget.
        Dispatch = "UnrestDispatch",
        --- Client -> server, request/response. The server never invokes the client.
        Invoke = "UnrestInvoke",
        --- Server -> client, channel replication.
        Publish = "UnrestPublish",
    }),

    --[[
        Hard ceilings applied to anything arriving from a client, before a handler sees it.
        These are not tuning knobs for gameplay: they bound the work a malicious client can
        make the server do.
    ]]
    Limits = table.freeze({
        --- Deepest nested table accepted in a payload.
        MaxPayloadDepth = 4,
        --- Most entries accepted in any one table of a payload.
        MaxPayloadEntries = 32,
        --- Longest string accepted anywhere in a payload.
        MaxStringLength = 256,
        --- Default per-player, per-command budget when a contract declares none.
        DefaultRateCount = 10,
        DefaultRateWindow = 1,
        --- Per-player budget across every command combined, so a client cannot shotgun
        --- many different cheap commands to get around per-command limits.
        GlobalRateCount = 60,
        GlobalRateWindow = 1,
        --- Seconds a client waits for an `Invoke` response before giving up.
        InvokeTimeout = 10,
        --- Rejections tolerated per player before `Net.Server` reports abuse to its hook.
        AbuseThreshold = 25,
    }),
}

return table.freeze(Constants)
