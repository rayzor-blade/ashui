package ashui.reactive;

interface ISignal<T> {
	/** The native signal that property bindings attach to. **/
	var ptr(default, null):hl.Abstract<"blinc_signal">;

	function get():T;
	function set(val:T):Void;
}
