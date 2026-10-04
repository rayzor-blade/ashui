package ashui.ui;

import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	The elements a template builds under one `ref=`, each item of a `<for>`
	its own, in the order they were built:

	    var rows = new RefList<Div>();
	    <for {item in items}><div ref={rows}>{item}</div></for>;
	    query(rows).onClick(e -> pick(e));

	An element joins it as it is built and leaves when its owner disposes
	it, as an item does when its value leaves the list. Reading it with
	`get` in a computed or watch follows it. `query` on one does what it is
	told to every element in it, and to each that joins later.
**/
class RefList<T:Element> {
	final current = Signal.make(([] : Array<Element>));

	public function new() {}

	/** The elements, in the order built; read in a computed or watch, followed. **/
	public function get():Array<T>
		return cast current.get();

	/** How many it holds; followed as `get` is. **/
	public function length():Int
		return current.get().length;

	/** Adds `element` until the owner it was built under is disposed. What `ref=` does. **/
	public function bind(element:T):Void {
		current.set(current.get().concat([element]));
		if (Owner.current != null)
			Owner.onCleanup(() -> current.set(current.get().filter(e -> e != element)));
	}
}
