package ashui.reactive;

import ashui.core.externs.Handles;
/**
	What every signal class implements; code uses it as `Signal<T>`, which
	`Signal.make` returns.
**/
interface ISignal<T> {
	/** The native signal that property bindings attach to. **/
	var ptr(default, null):SignalHandle;

	function get():T;
	function set(val:T):Void;
}
