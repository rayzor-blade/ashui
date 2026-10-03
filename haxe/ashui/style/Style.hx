package ashui.style;

import ashui.layout.Node;

/**
	Properties to set on a node, made by `Tw.tw` from utility classes. Apply
	it with `style.apply(node)`, or `style={...}` on a `<div>` in hxx, where
	the element's own attributes then win over it. `and` adds another style
	whose properties win over this one's.
**/
abstract Style(Array<Node->Void>) {
	inline function new(setters:Array<Node->Void>)
		this = setters;

	@:noCompletion public static inline function of(setters:Array<Node->Void>):Style
		return new Style(setters);

	public function apply(node:Node):Void {
		for (set in this)
			set(node);
	}

	public inline function and(other:Style):Style
		return new Style(this.concat(cast other));
}
