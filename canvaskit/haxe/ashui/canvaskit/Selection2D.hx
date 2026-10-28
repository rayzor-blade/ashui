package ashui.canvaskit;

import ashui.reactive.Signal;

/**
	Reactive selection model for a 2D canvas.
	Reading the selected IDs in a drawing callback or reactive computation
	subscribes to selection changes.

	```haxe
	var selection = new Selection2D();
	selection.select("a");
	selection.has("a"); // true
	```
**/
class Selection2D {
	/** Selected IDs in selection order. **/
	public final ids = Signal.make(([] : Array<String>));

	public function new() {}

	public function has(id:String):Bool
		return ids.get().indexOf(id) >= 0;

	/** Selects only the given ID. **/
	public function select(id:String):Void
		set([id]);

	/** Replaces the selection with these IDs. **/
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

	/** Adds an ID, or removes it if already selected. **/
	public function toggle(id:String):Void
		has(id) ? remove(id) : add(id);

	public function clear():Void
		set([]);
}
