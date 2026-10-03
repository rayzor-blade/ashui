package ashui.reactive;

/**
	What every signal class implements; code uses it as `Signal<T>`, which
	`Signal.make` returns.
**/
interface ISignal<T> {
	/** The native signal that property bindings attach to. **/
	var ptr(default, null):hl.Abstract<"blinc_signal">;

	function get():T;
	function set(val:T):Void;
}
