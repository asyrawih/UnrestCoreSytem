--!strict
--[[
    Unrest / Constants

    Stringly-typed values more than one layer needs, and nothing a game names. An attribute
    name is never spelled twice here, so a typo is a nil index rather than a silent no-op.

    Command and channel names are deliberately absent. They belong to the game, which keeps
    its own names wherever it likes; the framework only ever handles them as opaque strings.
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
        --- Command dispatched on the Bridge when the element is activated. It reaches
        --- whatever registered `Bridge:Handle` for that name, and nothing else.
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
        --- Seconds of client-side debounce between activations, so a fat-fingered double
        --- click does not dispatch twice.
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
}

return table.freeze(Constants)
