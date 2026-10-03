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

	/** The props it was built with. **/
	public final props:Props;
	final children:Array<Element>;
	final parentOwner:Null<Owner>;
	var owner:Owner;

	public function new(props:Props, ?children:Array<Element>, ?tree:LayoutTree) {
		super(tree);
		this.props = props;
		this.children = children != null ? children : [];
		parentOwner = Owner.current;
		owner = new Owner(this.tree, parentOwner);
		var root = rendering == null;
		node = build(owner);
		if (root)
			roots.push(cast this);
	}

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
		their values. Components the old render built are built afresh, so
		their own state starts over.
	**/
	public function rerender():Void {
		if (node == null)
			return;
		var next = new Owner(tree, parentOwner);
		var fresh = build(next);
		tree.replaceNode(node, fresh);
		owner.dispose();
		owner = next;
		node = fresh;
	}

	override public function remove():Void {
		roots.remove(cast this);
		owner.dispose();
		node = null;
	}

	/** Renders every root component again; see `HotReload`. **/
	@:noCompletion public static function rerenderRoots():Void {
		for (component in roots.copy())
			component.rerender();
	}
}
