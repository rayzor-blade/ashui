package ashui.ui;

/**
	Hot reload for development, on Ash.

	Run the program with `ash --hot-reload` (hybrid or jit mode; the
	interpreter alone ignores the flag) and call `HotReload.check()` once per
	frame; `WindowedApp` does when built with `-D ashui_hot_reload`, which
	release builds leave off to skip the per-frame file check.

	When the .hl file has changed, Ash swaps in the new method bodies, and
	every component no other component built renders again from the new
	code, keeping its fields, `@:state` included. The components that render
	builds take over the `@:state` of the ones built before them in the same
	place (see `Component.rerender`).

	Ash takes edits to method bodies, a template's new reactive expressions
	and callbacks, new classes such as a new child component, and methods
	added to or removed from a class; what it refuses it names, and the
	program keeps running the old code. Elsewhere `check()` does nothing.
**/
class HotReload {
	#if ashui_hot_reload
	/**
		Present only in a `-D ashui_hot_reload` build, whose `@:state`
		accessors make a field's signal on first use: how Ash tells that a
		state field a reload adds is safe to leave null on live instances.
	**/
	@:keep @:noCompletion public static var stateOnFirstUse = true;
	#end

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
