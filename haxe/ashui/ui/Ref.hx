package ashui.ui;

import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	A reactive reference to an element created by HXX:

	```haxe
	var panel = new Ref<Div>();
	var view = <div ref={panel} class="rounded-3xl">...</div>;
	panel.get().node.set(Prop.Opacity, 0.5);
	```

	The reference type must match the element type: `Ref<Div>` for `<div>`,
	`Ref<Card>` for `<card>`. HXX sets the reference during construction and
	clears it when the element's owner is disposed.

	A reference inside `<if>` follows the current element. Inside `<for>`,
	it holds the last element built; use `RefList` to retain all items.
	Calling `get` inside a computed or watch tracks reference changes.
**/
class Ref<T:Element> {
	final current = Signal.make((null : Null<Element>));

	public function new() {}

	/**
		Returns the current element, or null before construction and after disposal. Reactive reads track changes.
	**/
	public function get():Null<T>
		return cast current.get();

	/** Returns whether an element is bound. Reactive readers subscribe to changes. **/
	public function bound():Bool
		return current.get() != null;

	/** Binds an element until replaced or its owner is disposed. Called by HXX `ref` attributes. **/
	public function bind(element:T):Void {
		current.set(element);
		if (Owner.current != null)
			Owner.onCleanup(() -> if (current.get() == element) current.set(null));
	}
}
