package ashui.components;

/** A component's size, as its `data-size` attribute: `sm`, `md` (the default) or `lg`. **/
enum abstract Size(String) to String {
	var Sm = "sm";
	var Md = "md";
	var Lg = "lg";
}
