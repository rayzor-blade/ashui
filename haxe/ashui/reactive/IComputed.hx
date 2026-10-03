package ashui.reactive;

/**
	What every computed class implements; code uses it as `Computed<T>`,
	which `Computed.make` returns.
**/
interface IComputed<T> {
	/** The native computed that property bindings attach to. **/
	var ptr(default, null):hl.Abstract<"blinc_computed">;

	function get():T;
}
