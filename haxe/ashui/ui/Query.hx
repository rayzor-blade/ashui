package ashui.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#else
import ashui.css.Identity;
import ashui.input.Events;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.reactive.Watch;
#end

/**
	Updates element handlers, focus, attributes, classes and properties.
	Methods return the query so calls can be chained:

	```haxe
	query(button).onClick(_ -> save()).focusable();
	query(panel).addClass("open").set(Prop.Opacity, 0.9);
	query(".row", list).onClick(e -> pick(e)).removeClass("stale");
	```

	Targets can be an element, `Ref`, `RefList`, or a selector with an element
	or tree to search. Unsupported targets and invalid literal selectors are
	compile errors.

	Element and selector queries update the current matches once. A query on
	a `Ref` reapplies its configuration when the reference changes. A query
	on a `RefList` applies to current elements and those added later.
**/
class Query {
	/** Creates a query for an element, `Ref`, `RefList`, or selector. Selector queries require an element or tree in `within`. **/
	public static macro function query(target:Expr, ?within:Expr):Expr {
		var type = try Context.typeof(target) catch (_:Dynamic) Context.error("query: cannot type this", target.pos);
		inline function is(name:String)
			return try Context.unify(type, Context.getType(name)) catch (_:Dynamic) false;
		var isRef = switch Context.follow(type) {
			case TInst(_.get() => {pack: ['ashui', 'ui'], name: 'Ref'}, _): true;
			case _: false;
		}
		var isRefList = switch Context.follow(type) {
			case TInst(_.get() => {pack: ['ashui', 'ui'], name: 'RefList'}, _): true;
			case _: false;
		}
		var noWithin = within == null || switch within.expr {
			case EConst(CIdent('null')): true;
			case _: false;
		};
		if (isRefList) {
			if (!noWithin)
				Context.error('query: a RefList takes no place to look', within.pos);
			return macro @:pos(target.pos) ashui.ui.Query.ofRefList($target);
		}
		if (isRef || is('ashui.layout.Element')) {
			if (!noWithin)
				Context.error('query: an element or a Ref takes no place to look', within.pos);
			return isRef ? macro @:pos(target.pos) ashui.ui.Query.ofRef($target) : macro @:pos(target.pos) ashui.ui.Query.ofElement($target);
		}
		if (is('String')) {
			if (noWithin)
				Context.error('query: a selector needs where to look, an element or a tree: query("#save", page)', target.pos);
			switch target.expr {
				case EConst(CString(text, _)):
					var error = ashui.css.CssCompiler.selectorError(text);
					if (error != null)
						Context.error('query: $error', target.pos);
				case _:
			}
			var whereType = Context.typeof(within);
			var inTree = try Context.unify(whereType, Context.getType('ashui.layout.LayoutTree')) catch (_:Dynamic) false;
			return inTree ? macro @:pos(target.pos) ashui.ui.Query.select($target, $within,
				null) : macro @:pos(target.pos) ashui.ui.Query.select($target, $within.tree, $within.node.id);
		}
		return Context.error('query takes an element, a Ref, or a selector and where to look, not ${haxe.macro.TypeTools.toString(type)}', target.pos);
	}

	#if !macro
	final tree:Null<LayoutTree>;

	/** Returns the nodes currently targeted by the query. **/
	final current:Void->Array<Node>;

	/** Operations to replay when a reference gains elements. Null for a one-time query. **/
	final replay:Null<Array<Node->Void>>;

	function new(tree:Null<LayoutTree>, current:Void->Array<Node>, replay:Null<Array<Node->Void>>) {
		this.tree = tree;
		this.current = current;
		this.replay = replay;
	}

	@:noCompletion public static function ofElement(element:Element):Query {
		var nodes = [element.node];
		return new Query(element.tree, () -> nodes, null);
	}

	@:noCompletion public static function ofRef<T:Element>(ref:Ref<T>):Query {
		var replay:Array<Node->Void> = [];
		var held:Null<T> = null;
		var q = new Query(null, () -> {
			var e = ref.get();
			e == null ? [] : [e.node];
		}, replay);
		// Each element the ref comes to hold is told what this was.
		new Watch(() -> ref.get(), e -> {
			if (e == null || e == held)
				return;
			held = e;
			for (f in replay)
				f(e.node);
		});
		held = ref.get();
		return q;
	}

	@:noCompletion public static function ofRefList<T:Element>(list:RefList<T>):Query {
		var replay:Array<Node->Void> = [];
		var told:Array<Element> = [];
		var q = new Query(null, () -> [for (e in list.get()) e.node], replay);
		// Each element that joins the list is told what this was; those already in it were told as it was said.
		new Watch(() -> list.get(), now -> {
			told = told.filter(e -> now.indexOf(cast e) >= 0);
			for (e in now)
				if (told.indexOf(e) < 0) {
					told.push(e);
					for (f in replay)
						f(e.node);
				}
		});
		told = [for (e in list.get()) e];
		return q;
	}

	@:noCompletion public static function select(selector:String, tree:LayoutTree, root:Null<haxe.Int64>):Query {
		var start = root != null ? root : tree.root != null ? tree.root.id : null;
		// Each element's own node, which its Interaction is kept by.
		var nodes = start == null ? [] : [
			for (id in ashui.css.Css.query(tree, start, selector)) Identity.of(tree, id).node
		];
		return new Query(tree, () -> nodes, null);
	}

	/** Applies an operation to current nodes and replays it for future reference targets. **/
	function each(f:Node->Void):Query {
		if (replay != null)
			replay.push(f);
		for (n in current())
			f(n);
		return this;
	}

	function treeOf(n:Node):LayoutTree
		return n.tree != null ? n.tree : tree;

	// --- Handlers, as `Interaction` binds them ---

	public function onClick(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onClick(handler));

	public function onPointerDown(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onPointerDown(handler));

	public function onPointerUp(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onPointerUp(handler));

	public function onPointerMove(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onPointerMove(handler));

	public function onPointerEnter(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onPointerEnter(handler));

	public function onPointerLeave(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onPointerLeave(handler));

	public function onWheel(handler:PointerEvent->Void):Query
		return each(n -> Interaction.of(n).onWheel(handler));

	public function onKeyDown(handler:KeyEvent->Void):Query
		return each(n -> Interaction.of(n).onKeyDown(handler));

	public function onKeyUp(handler:KeyEvent->Void):Query
		return each(n -> Interaction.of(n).onKeyUp(handler));

	public function onTextInput(handler:TextInputEvent->Void):Query
		return each(n -> Interaction.of(n).onTextInput(handler));

	public function onComposition(handler:CompositionEvent->Void):Query
		return each(n -> Interaction.of(n).onComposition(handler));

	public function onFocus(handler:FocusEvent->Void):Query
		return each(n -> Interaction.of(n).onFocus(handler));

	public function onBlur(handler:FocusEvent->Void):Query
		return each(n -> Interaction.of(n).onBlur(handler));

	// --- Input state ---

	/** Allows matched elements to receive focus through Tab or a pointer press. **/
	public function focusable(value = true):Query
		return each(n -> Interaction.of(n).setFocusable(value));

	/** Disables matched elements and applies `:disabled`. Accepts reactive values. **/
	public function disabled(value:IntoReactive<Bool>):Query
		return each(n -> Interaction.of(n).setDisabled(value));

	/** Focuses the first matched element. Set `visible` to show the keyboard focus ring. **/
	public function focus(visible = false):Query {
		var n = current()[0];
		if (n != null)
			ashui.input.Focus.set(Interaction.of(n), visible);
		return this;
	}

	/** Simulates a pointer press and release at the first element center. Useful for scripts and tests. **/
	public function click():Query {
		var n = current()[0];
		if (n == null)
			return this;
		var t = treeOf(n), b = t.getBounds(n);
		if (b == null)
			return this;
		ashui.input.Pointer.move(t, b.x + b.width / 2, b.y + b.height / 2);
		ashui.input.Pointer.press(t);
		ashui.input.Pointer.release(t);
		return this;
	}

	// --- What CSS sees ---

	/** Sets an attribute such as `data-state`. A null value removes the attribute. **/
	public function attr(name:String, value:Null<String>):Query
		return each(n -> identity(n).setAttribute(name, value));

	/** Returns an attribute from the first match, or null when absent. **/
	public function getAttr(name:String):Null<String> {
		var n = current()[0];
		return n == null ? null : identity(n).attribute(name);
	}

	public function addClass(name:String):Query
		return each(n -> identity(n).addClasses([name]));

	public function removeClass(name:String):Query
		return each(n -> {
			var i = identity(n);
			i.setClasses([for (c in i.classes()) if (c != name) c]);
		});

	/** Adds a class when `on` is true, or removes the class when false. **/
	public function toggleClass(name:String, on:Bool):Query
		return on ? addClass(name) : removeClass(name);

	/** Returns whether the first match has the class. **/
	public function hasClass(name:String):Bool {
		var n = current()[0];
		return n != null && identity(n).hasClass(name);
	}

	// --- Properties and where it is ---

	/** Sets a layout or visual property. Signals and computeds update the property reactively. **/
	public function set<T>(prop:Prop<T>, value:IntoReactive<T>):Query
		return each(n -> n.set(prop, value));

	/** Returns the first match bounds from the last layout pass, or null when no element matches. **/
	public function bounds():Null<ashui.layout.Bounds> {
		var n = current()[0];
		return n == null ? null : treeOf(n).getBounds(n);
	}

	/** Returns the current number of matched nodes. **/
	public function count():Int
		return current().length;

	/** Returns the currently matched nodes. **/
	public function nodes():Array<Node>
		return current().copy();

	function identity(n:Node):Identity {
		var t = treeOf(n);
		var i = Identity.of(t, n.id);
		return i != null ? i : Identity.register(t, n, "div");
	}
	#end
}
