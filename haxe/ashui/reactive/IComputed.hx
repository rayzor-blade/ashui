package ashui.reactive;

import ashui.core.externs.Handles;
/** The interface implemented by computed storage types. Use `Computed<T>` in application code. **/
interface IComputed<T> {
	/** The native computed that property bindings attach to. **/
	var ptr(default, null):ComputedHandle;

	function get():T;
}
