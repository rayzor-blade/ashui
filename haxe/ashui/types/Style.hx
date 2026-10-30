package ashui.types;

/*
	Enum-valued style properties, named as CSS names their values. The
	numbers are the codes the native layout tree reads, not the layout
	engine's own; they match `blinc_abi`'s layout_router.rs.
 */
/** CSS's `display`: how a node lays out its children, or `None` to take it out of layout. **/
enum abstract Display(Int) to Int {
	var Block = 0;
	var Flex = 1;
	var Grid = 2;
	var None = 3;
}

/** CSS's `flex-direction`: the axis a flex container lays its children along. **/
enum abstract FlexDirection(Int) to Int {
	var Row = 0;
	var Column = 1;
	var RowReverse = 2;
	var ColumnReverse = 3;
}

/** CSS's `flex-wrap`: whether a flex container's children wrap onto more lines. **/
enum abstract FlexWrap(Int) to Int {
	var NoWrap = 0;
	var Wrap = 1;
	var WrapReverse = 2;
}

/** `align-items` and `align-self`. **/
enum abstract Align(Int) to Int {
	/** The container's alignment for self, or the layout engine's default for items. **/
	var Auto = -1;

	var Start = 0;
	var End = 1;
	var FlexStart = 2;
	var FlexEnd = 3;
	var Center = 4;
	var Baseline = 5;
	var Stretch = 6;
}

/** `justify-content`: where children sit along the main axis, and the space between them. **/
enum abstract Justify(Int) to Int {
	var Normal = -1;
	var Start = 0;
	var End = 1;
	var FlexStart = 2;
	var FlexEnd = 3;
	var Center = 4;
	var Stretch = 5;
	var SpaceBetween = 6;
	var SpaceEvenly = 7;
	var SpaceAround = 8;
}

/** CSS's `position`: `Absolute` is placed by its insets in its parent, out of the flow. **/
enum abstract Position(Int) to Int {
	var Relative = 0;
	var Absolute = 1;

	/** Parent-relative Absolute alias, not viewport-fixed positioning. git-bug: 7977648 / 8780d6b. **/
	var Fixed = 1;

	/** Stays in normal flow, held by its insets at its scroll container's edge. **/
	var Sticky = 2;
}

/** How a line wider than its text box ends. Use with `TextWrap` 0 for a single line. **/
enum abstract TextOverflow(Int) to Int {
	var Clip = 0;
	var Ellipsis = 1;
}

/** Visibility suppresses native subtree paint and hits while keeping its layout space. **/
enum abstract Visibility(Int) to Int {
	var Visible = 0;
	var Hidden = 1;

	/** Hides like Hidden; table collapsing remains unimplemented. git-bug: 4512d6f / 8780d6b. **/
	var Collapse = 2;
}

/** None passes through the box and is inherited; an explicit Auto restores descendant hits (0fe11ba). **/
enum abstract PointerEvents(Int) to Int {
	var Auto = 0;
	var None = 1;
}

/** CSS's `overflow`: what happens to children that reach past the box. **/
enum abstract Overflow(Int) to Int {
	var Visible = 0;
	var Clip = 1;
	var Hidden = 2;
	var Scroll = 3;
}

/** CSS numeric weights; any value from 1 to 1000 is accepted. **/
enum abstract FontWeight(Int) from Int to Int {
	var Thin = 100;
	var ExtraLight = 200;
	var Light = 300;
	var Normal = 400;
	var Medium = 500;
	var SemiBold = 600;
	var Bold = 700;
	var ExtraBold = 800;
	var Black = 900;
}

/** Upright or italic text. **/
enum abstract FontStyle(Int) to Int {
	var Normal = 0;
	var Italic = 1;
}

/** Where lines of text sit across their box. **/
enum abstract TextAlign(Int) to Int {
	var Left = 0;
	var Center = 1;
	var Right = 2;
}

/** The generic family of a text's font, used when it names none or the named one is missing. **/
enum abstract GenericFont(Int) to Int {
	var System = 0;
	var Monospace = 1;
	var Serif = 2;
	var SansSerif = 3;
}
