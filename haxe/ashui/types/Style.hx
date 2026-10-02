package ashui.types;

/*
	Enum-valued style properties. The numbers are the codes `blinc_abi`
	matches on (layout_router.rs), not Taffy's own discriminants.
*/

enum abstract Display(Int) to Int {
	var Block = 0;
	var Flex = 1;
	var Grid = 2;
	var None = 3;
}

enum abstract FlexDirection(Int) to Int {
	var Row = 0;
	var Column = 1;
	var RowReverse = 2;
	var ColumnReverse = 3;
}

enum abstract FlexWrap(Int) to Int {
	var NoWrap = 0;
	var Wrap = 1;
	var WrapReverse = 2;
}

/** `align-items` and `align-self`. **/
enum abstract Align(Int) to Int {
	var Start = 0;
	var End = 1;
	var FlexStart = 2;
	var FlexEnd = 3;
	var Center = 4;
	var Baseline = 5;
	var Stretch = 6;
}

enum abstract Justify(Int) to Int {
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

enum abstract Position(Int) to Int {
	var Relative = 0;
	var Absolute = 1;
}

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

enum abstract FontStyle(Int) to Int {
	var Normal = 0;
	var Italic = 1;
}

enum abstract TextAlign(Int) to Int {
	var Left = 0;
	var Center = 1;
	var Right = 2;
}

enum abstract GenericFont(Int) to Int {
	var System = 0;
	var Monospace = 1;
	var Serif = 2;
	var SansSerif = 3;
}
