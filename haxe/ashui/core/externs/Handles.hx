package ashui.core.externs;

/**
	What the native handles are: HashLink's abstract handles from
	`blinc_abi.hdll`, or under `-D ashui_caribou` the objects of the
	`blinc_abi` Caribou plugin's classes.
**/
#if ashui_caribou
typedef TreeHandle = blinc_abi.Tree;
typedef SignalHandle = blinc_abi.Signal;
typedef ComputedHandle = blinc_abi.Computed;
typedef ValueHandle = blinc_abi.StyleValue;
typedef CssHandle = blinc_abi.Css;
typedef SheetHandle = blinc_abi.Sheet;
#else
typedef TreeHandle = hl.Abstract<"blinc_tree">;
typedef SignalHandle = hl.Abstract<"blinc_signal">;
typedef ComputedHandle = hl.Abstract<"blinc_computed">;
typedef ValueHandle = hl.Abstract<"blinc_value">;
typedef CssHandle = hl.Abstract<"blinc_css">;
typedef SheetHandle = hl.Abstract<"blinc_css_sheet">;
#end
