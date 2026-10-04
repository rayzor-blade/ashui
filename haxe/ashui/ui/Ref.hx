package ashui.ui;

import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	A name for an element a template builds, so code can reach it without
	the template being broken up:

	    var panel = new Ref<Div>();
	    hxx('<div ref={panel} class="rounded-3xl">...</div>');
	    panel.get().node.set(Prop.Opacity, 0.5);

	`ref={x}` takes a `Ref` of the element's own type: a `Ref<Div>` on a
	`<div>`, a `Ref<Card>` on a `<card>`; another is a compile error. It is
	set as the element is built and cleared when the element's owner
	disposes it, so under `<if>` it follows the element that is there now.
	Reading it with `get` in a computed or watch follows it, as a signal's
	does. Under `<for>`, each item's element sets it in turn, so it holds the
	last built.
**/
class Ref<T:Element> {
	final current = Signal.make((null : Null<Element>));

	public function new() {}

	/** The element, or null before it is built and after it is gone; read in a computed or watch, followed. **/
	public function get():Null<T>
		return cast current.get();

	/** Whether it holds an element now; followed as `get` is. **/
	public function bound():Bool
		return current.get() != null;

	/** Holds `element` until the owner it was built under is disposed, or another is bound. What `ref=` does. **/
	public function bind(element:T):Void {
		current.set(element);
		if (Owner.current != null)
			Owner.onCleanup(() -> if (current.get() == element) current.set(null));
	}
}
