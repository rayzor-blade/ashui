package ashui.ui;

import ashui.layout.Element;
import ashui.layout.LayoutTree;
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
	public final props:Props;
	final children:Array<Element>;
	final owner:Owner;

	public function new(props:Props, ?children:Array<Element>, ?tree:LayoutTree) {
		super(tree);
		this.props = props;
		this.children = children != null ? children : [];
		owner = new Owner(this.tree);
		node = owner.run(render).node;
	}

	/** Builds the component's element; `props` and `children` are set. **/
	abstract function render():Element;

	override public function remove():Void {
		owner.dispose();
		node = null;
	}
}
