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
	One handle on elements, to drive them from code: their handlers, focus,
	attributes, classes and properties, each call returning the handle.

	    query(button).onClick(_ -> save()).focusable();
	    query(panel).addClass("open").set(Prop.Opacity, 0.9);
	    query(".row", list).onClick(e -> pick(e)).removeClass("stale");

	`query` takes an element, a `Ref`, a `RefList`, or a selector with where to look, an
	element or a tree; anything else is a compile error, and a quoted
	selector is read at compile time. On a `Ref` what it is told is kept,
	and done again on each element the ref comes to hold; on an element or
	a selector it is done now, to what is there now, as
	`querySelectorAll`'s list is what matched when it ran. On a `RefList`
	it is done to every element in it, and to each that joins later.
**/
class Query {
	/** A handle on `target`: an element, a `Ref`, or a selector with `within`, an element or a tree, to look under. **/
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
					try ashui.css.CssParser.selectors(text) catch (e:String) Context.error('query: $e', target.pos);
				case _:
			}
			var whereType = Context.typeof(within);
			var inTree = try Context.unify(whereType, Context.getType('ashui.layout.LayoutTree')) catch (_:Dynamic) false;
			return inTree ? macro @:pos(target.pos) ashui.ui.Query.select($target, $within, null) : macro @:pos(target.pos) ashui.ui.Query.select($target,
				$within.tree, $within.node.id);
		}
		return Context.error('query takes an element, a Ref, or a selector and where to look, not ${haxe.macro.TypeTools.toString(type)}', target.pos);
	}

	#if !macro
	final tree:Null<LayoutTree>;

	/** What it acts on now. **/
	final current:Void->Array<Node>;

	/** What it was told, done again to each element a ref comes to hold; null when it acts once. **/
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
		var nodes = start == null ? [] : [for (id in ashui.css.Css.query(tree, start, selector)) Identity.of(tree, id).node];
		return new Query(tree, () -> nodes, null);
	}

	/** Does `f` to each element now, and to each a ref comes to hold. **/
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

	/** Whether Tab and a press give it focus. **/
	public function focusable(value = true):Query
		return each(n -> Interaction.of(n).setFocusable(value));

	/** Whether it takes no input and matches `:disabled`; a signal or computed is followed. **/
	public function disabled(value:IntoReactive<Bool>):Query
		return each(n -> Interaction.of(n).setDisabled(value));

	/** Gives the first focus, a ring showing when `visible`, as the keyboard gives it. **/
	public function focus(visible = false):Query {
		var n = current()[0];
		if (n != null)
			ashui.input.Focus.set(Interaction.of(n), visible);
		return this;
	}

	/** A press and release at the middle of the first, as the pointer makes them: for scripts and tests. **/
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

	/** Sets attribute `name`, or removes it when `value` is null; `data-state` and the like. **/
	public function attr(name:String, value:Null<String>):Query
		return each(n -> identity(n).setAttribute(name, value));

	/** Attribute `name` of the first, or null. **/
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

	/** Adds `name` when `on`, else removes it. **/
	public function toggleClass(name:String, on:Bool):Query
		return on ? addClass(name) : removeClass(name);

	/** Whether the first has class `name`. **/
	public function hasClass(name:String):Bool {
		var n = current()[0];
		return n != null && identity(n).hasClass(name);
	}

	// --- Properties and where it is ---

	/** Binds layout or visual property `prop`, as an attribute would: a constant, or a signal or computed followed. **/
	public function set<T>(prop:Prop<T>, value:IntoReactive<T>):Query
		return each(n -> n.set(prop, value));

	/** The first one's box as last laid out, or null. **/
	public function bounds():Null<ashui.layout.Bounds> {
		var n = current()[0];
		return n == null ? null : treeOf(n).getBounds(n);
	}

	/** How many it acts on now. **/
	public function count():Int
		return current().length;

	/** Its nodes now. **/
	public function nodes():Array<Node>
		return current().copy();

	function identity(n:Node):Identity {
		var t = treeOf(n);
		var i = Identity.of(t, n.id);
		return i != null ? i : Identity.register(t, n, "div");
	}
	#end
}
