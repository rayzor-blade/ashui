package ashui.ui;

import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	Collects elements assigned to the same HXX `ref`, in construction order:

	```haxe
	var rows = new RefList<Div>();
	<for {item in items}><div ref={rows}>{item}</div></for>;
	query(rows).onClick(e -> pick(e));
	```

	Elements join during construction and leave when their owners are disposed.
	Calling `get` inside a computed or watch tracks membership changes.
	A query applies to current members and any elements added later.
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
