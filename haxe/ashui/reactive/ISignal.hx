package ashui.reactive;

import ashui.core.externs.Handles;
/** The interface implemented by signal storage types. Use `Signal<T>` in application code. **/
interface ISignal<T> {
	/** The native signal that property bindings attach to. **/
	var ptr(default, null):SignalHandle;

	function get():T;
	function set(val:T):Void;
}
