package ashui.ui;

/**
	Hot reload for development, on Ash.

	Run the program with `ash --hot-reload` (hybrid or jit mode; the
	interpreter alone ignores the flag) and call `HotReload.check()` once per
	frame. When the .hl file has changed, Ash swaps in the new method bodies,
	and every component no other component built renders again from the new
	code, keeping its fields, `@:state` included.

	Ash replaces method bodies only: adding, removing or reordering methods,
	fields or statics is not supported. A template's reactive expressions and
	callbacks are methods of their own, so adding or removing one counts as
	adding or removing a method. Elsewhere `check()` does nothing.
**/
class HotReload {
	/** True when the program was reloaded and its root components rendered again. **/
	public static function check():Bool {
		#if hl
		if (!hl.Api.checkReload())
			return false;
		Component.rerenderRoots();
		return true;
		#else
		return false;
		#end
	}
}
