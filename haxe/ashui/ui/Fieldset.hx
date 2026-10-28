package ashui.ui;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef FieldsetProps = {
	/** Disables all descendant controls except those in the first `<legend>`. **/
	?disabled:IntoReactive<Bool>,

	?id:String,
	?name:String
}

/**
	A group of form controls, written as `<fieldset>` in HXX.

	Use a first-child `<legend>` for the caption. Disabling the fieldset disables
	its controls, including controls added later, except those inside the first
	legend. The fieldset exposes `[disabled]`; disabled controls match `:disabled`.
**/
class Fieldset extends Component<FieldsetProps> {
	function render():Element {
		var box = new Div({tag: "fieldset", id: props.id}, children);
		var identity = ashui.css.Identity.of(box.tree, box.node.id);
		if (props.name != null)
			identity.setAttribute("name", props.name);
		var disabled = switch props.disabled {
			case null: return box;
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var tree = box.tree;
		var marked:Array<Interaction> = [];
		// The controls it holds now: every interaction under it, those in its first legend aside.
		function mark() {
			var on = disabled.get();
			var now = on ? held(tree, box) : [];
			for (i in marked)
				if (now.indexOf(i) < 0)
					i.disableFrom(this, false);
			for (i in now)
				i.disableFrom(this, true);
			marked = now;
		}
		new Watch(() -> disabled.get(), on -> {
			identity.setAttribute("disabled", on ? "" : null);
			mark();
		});
		ashui.layout.AfterChildren.watch(tree, "fieldset " + haxe.Int64.toStr(box.node.id),
			parent -> disabled.get() && (parent == box.node.id || tree.ancestors(parent).indexOf(box.node.id) >= 0), mark);
		Owner.onCleanup(() -> for (i in marked)
			i.disableFrom(this, false));
		return box;
	}

	static function held(tree:LayoutTree, box:Div):Array<Interaction> {
		var out = [];
		var kids = tree.children(box.node.id);
		var legend = Lambda.find(kids, k -> {
			var id = ashui.css.Identity.of(tree, k);
			id != null
			&& id.types.indexOf("legend") >= 0;
		});
		// Only a legend that comes first exempts what it holds.
		if (legend != null && kids[0] != legend)
			legend = null;
		var stack = kids.filter(k -> k != legend);
		while (stack.length > 0) {
			var at = stack.pop();
			var i = Interaction.byId(tree, at);
			if (i != null)
				out.push(i);
			for (child in tree.children(at))
				stack.push(child);
		}
		return out;
	}
}
