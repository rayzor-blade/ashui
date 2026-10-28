package ashui.ui;

/**
	Reloads component code during development on Ash.

	Run with `ash --hot-reload` in hybrid or JIT mode. Build with
	`-D ashui_hot_reload` so `WindowedApp` calls `check()` each frame;
	release builds omit the flag and its file checks.

	When the bytecode changes, Ash replaces method bodies and root components
	render again. Fields retain their values, including `@:state`. Replacement
	children inherit state as described by `Component.rerender`.

	Supported changes include method bodies, reactive expressions, callbacks,
	new classes, and added or removed methods. Rejected changes are reported
	and the program keeps running the previous code. `check()` has no effect
	on other runtimes or in interpreter-only mode.
**/
class HotReload {
	#if ashui_hot_reload
	/**
		Marks hot-reload builds whose state accessors initialize new signals on
		first use. Ash can then leave newly added state fields null in existing instances.
	**/
	@:keep @:noCompletion public static var stateOnFirstUse = true;
	#end

	/** Checks for a reload. Returns true if new code was loaded and root components rendered again. **/
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
