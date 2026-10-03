package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;

/**
	A component: the element `render` builds from typed props, usually a
	`Div`. The component is that element, not a box around it.

	hxx builds `<Tag a={x}>kids</Tag>` as `new Tag({a: x}, [kids])`, checks
	each attribute against `Props`, and makes a prop typed `IntoReactive<T>`
	follow what its attribute expression reads, as `Div` attributes do.

	`render` runs under the component's own owner, so what it creates is
	cleaned up when the component is removed. Field initializers run before
	it, so a component can keep signals in fields; `@:state var x:T = init`
	does that for it, and `function render() '<template>'` is a template
	(see `ComponentBuilder`).
**/
@:autoBuild(ashui.ui.ComponentBuilder.build())
abstract class Component<Props> extends Element {
	/** Live components that no other component's render built; `HotReload` renders these again. **/
	static final roots:Array<Component<Dynamic>> = [];

	/** The component whose render is running, if any. **/
	static var rendering:Null<Component<Dynamic>> = null;

	/** Each live component by the owner its render runs under. **/
	static final hosts = new haxe.ds.ObjectMap<Owner, Component<Dynamic>>();

	/** The props it was built with. **/
	public final props:Props;
	final children:Array<Element>;
	final parentOwner:Null<Owner>;
	var owner:Owner;

	/**
		The component this one was built under, if any: the one rendering, or
		for one built later, as a `<for>` builds a new item, the nearest
		whose owner is an ancestor of the current one.
	**/
	final builder:Null<Component<Dynamic>>;

	/** Components built under this one, in the order they were built. **/
	var built:Array<Component<Dynamic>> = [];

	/** While rendering again, the components the last render built not yet taken over. **/
	var previous:Null<Array<Component<Dynamic>>> = null;

	public function new(props:Props, ?children:Array<Element>, ?tree:LayoutTree) {
		super(tree);
		this.props = props;
		this.children = children != null ? children : [];
		parentOwner = Owner.current;
		owner = new Owner(this.tree, parentOwner);
		hosts.set(owner, cast this);
		builder = rendering != null ? rendering : hostOf(parentOwner);
		// Under the owner this was built under, so it leaves the books with it.
		Owner.onCleanup(forget);
		if (builder == null) {
			node = build(owner);
			identify();
			roots.push(cast this);
			return;
		}
		builder.built.push(cast this);
		// Rendering again: take over the state of the component the last
		// render built in the same place, and match its children to ours.
		var old = builder.claim(Type.getClass(this));
		if (old != null) {
			__takeState(old);
			previous = old.built;
		}
		node = build(owner);
		identify();
		previous = null;
	}

	static function hostOf(owner:Null<Owner>):Null<Component<Dynamic>> {
		while (owner != null) {
			var host = hosts.get(owner);
			if (host != null)
				return host;
			owner = owner.parent;
		}
		return null;
	}

	/** Drops this one from the roots, its builder's list and the hosts. **/
	function forget():Void {
		roots.remove(cast this);
		if (builder != null)
			builder.built.remove(cast this);
		hosts.remove(owner);
		node = null;
	}

	/** Adds the component's tag to its node's identity, so a CSS type selector, `counter-view`, matches it. **/
	function identify():Void {
		if (node != null)
			ashui.css.Identity.register(tree, node.id, tag(Type.getClass(this)));
	}

	/** A component class's tag, as hxx spells it: `CounterView` is `counter-view`. **/
	public static function tag(c:Class<Dynamic>):String {
		var name = Type.getClassName(c);
		name = name.substr(name.lastIndexOf(".") + 1);
		return ~/([a-z0-9])([A-Z])/g.map(name, r -> r.matched(1) + "-" + r.matched(2)).toLowerCase();
	}

	/** Removes and returns the first component the last render built of class `c`, if any. **/
	function claim(c:Class<Dynamic>):Null<Component<Dynamic>> {
		if (previous == null)
			return null;
		for (i => old in previous)
			if (Type.getClass(old) == c) {
				previous.splice(i, 1);
				return old;
			}
		return null;
	}

	/** Takes `old`'s `@:state` signals for this one's; `ComponentBuilder` generates it for classes that have any. **/
	@:noCompletion function __takeState(old:Component<Dynamic>):Void {}

	/** Builds the component's element; `props` and `children` are set. **/
	abstract function render():Element;

	function build(into:Owner):Node {
		var outer = rendering;
		rendering = cast this;
		try {
			var built = into.run(render).node;
			rendering = outer;
			return built;
		} catch (e:haxe.Exception) {
			rendering = outer;
			throw e;
		}
	}

	/**
		Runs `render` again and puts its element where the old one was, then
		disposes what the old render created. Fields, `@:state` included, keep
		their values. A component the new render builds takes over the
		`@:state` of the one the old render built of the same class, the
		first of its class for the first and so on, and so do theirs.
	**/
	public function rerender():Void {
		if (node == null)
			return;
		var next = new Owner(tree, parentOwner);
		hosts.set(next, cast this);
		var last = built;
		previous = last.copy();
		built = [];
		var fresh = try build(next) catch (e:haxe.Exception) {
			hosts.remove(next);
			next.dispose();
			built = last;
			previous = null;
			throw e;
		}
		previous = null;
		tree.replaceNode(node, fresh);
		hosts.remove(owner);
		owner.dispose();
		owner = next;
		node = fresh;
		identify();
	}

	override public function remove():Void {
		owner.dispose();
		forget();
	}

	/** Renders every root component again; see `HotReload`. **/
	@:noCompletion public static function rerenderRoots():Void {
		for (component in roots.copy())
			component.rerender();
	}
}
