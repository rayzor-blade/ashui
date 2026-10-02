package ashui.reactive;

interface IComputed<T> {
	/** The native computed that property bindings attach to. **/
	var ptr(default, null):hl.Abstract<"blinc_computed">;

	function get():T;
}
