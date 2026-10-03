package ashui.types;

/**
	A style value a node's property takes: `Brush`, `Color`, `CornerRadius`,
	`CornerShape`, `Shadow`, `Transform` or `ClipPath`. Each holds its copy
	in the native library in `ptr`, which the layout tree reads when the
	value is set on a node; make a new value to change a property rather
	than changing one already set.
**/
interface IValue {
	var ptr(default, null):hl.Abstract<"blinc_value">;
}
