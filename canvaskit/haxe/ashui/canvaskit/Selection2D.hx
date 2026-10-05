package ashui.canvaskit;

import ashui.reactive.Signal;

/**
	The ids selected on a 2D canvas, as a signal: what reads it draws or
	acts again when it changes.

	```haxe
	var selection = new Selection2D();
	selection.select("a");
	selection.has("a"); // true
	```
**/
class Selection2D {
	/** The selected ids, in the order they were selected. **/
	public final ids = Signal.make(([] : Array<String>));

	public function new() {}

	public function has(id:String):Bool
		return ids.get().indexOf(id) >= 0;

	/** Selects `id` alone. **/
	public function select(id:String):Void
		set([id]);

	/** Selects these, and nothing else. **/
	public function set(next:Array<String>):Void {
		var now = ids.get();
		if (now.length == next.length && [for (i in 0...now.length) now[i] == next[i]].indexOf(false) < 0)
			return;
		ids.set(next.copy());
	}

	public function add(id:String):Void
		if (!has(id))
			ids.set(ids.get().concat([id]));

	public function remove(id:String):Void
		if (has(id))
			ids.set(ids.get().filter(x -> x != id));

	/** Adds `id`, or takes it out when it is selected. **/
	public function toggle(id:String):Void
		has(id) ? remove(id) : add(id);

	public function clear():Void
		set([]);
}
