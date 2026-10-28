package ashui.components;

/** Shared component sizes: `sm`, `md` (default), and `lg`, exposed through the `data-size` attribute. **/
enum abstract Size(String) to String {
	var Sm = "sm";
	var Md = "md";
	var Lg = "lg";
}
