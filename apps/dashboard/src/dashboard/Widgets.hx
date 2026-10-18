package dashboard;

import ashui.css.Identity;
import ashui.layout.Element;
import ashui.reactive.Computed;
import ashui.types.Style;

/** The small pieces the pages are made of. **/
class Widgets {
	/** An icon, `classes` on it: `size-5`, or a colour. **/
	public static function icon(document:ashui.svg.Icon, classes:String):Element {
		var svg = new ashui.ui.Svg(document);
		Identity.of(svg.tree, svg.node.id).addClasses(classes.split(" "));
		return svg;
	}

	/** `el` with its attribute `name` present while `condition` is true, which the stylesheet's `[name]` selects. **/
	public static function flag(el:Element, name:String, condition:Void->Bool):Element {
		Identity.of(el.tree, el.node.id).bindBooleanAttribute(name, Computed.make(condition));
		return el;
	}

	/**
		`el`, `width` pixels wide, centred across a screen `screenWidth` wide and `bottom` pixels above its lower edge, in a box with
		no size: a pointer is the element's alone and passes through everywhere else. A full-width wrapper that passed the pointer
		through would pass it through its children as well (git-bug 0fe11ba).
	**/
	public static function dockedBottom(el:Element, screenWidth:Void->Float, width:Void->Float, bottom:Float):Element {
		var x = Computed.make(() -> Math.round((screenWidth() - width()) / 2) * 1.0);
		var w = Computed.make(width);
		return <div position={Absolute} left={0} bottom={0} width={0} height={0}>
			<div position={Absolute} left={x} bottom={bottom} width={w}>{el}</div>
		</div>;
	}

	/** A row of choices, one of which is `current`: a press on one calls `choose` with its place. **/
	public static function segments(labels:Array<String>, current:Void->Int, choose:Int->Void):Element {
		var items = [
			for (i => label in labels)
				flag(press(<div class="dash-seg flex items-center justify-center px-3" height={32} flexGrow={1}><text class="text-xs font-medium">${label}</text></div>,
					() -> choose(i)), "on", () -> current() == i)
		];
		return <div class="dash-segs flex flex-row gap-1 p-1">{items}</div>;
	}

	/**
		`f` as a text that is made again when a signal it reads changes. Markup follows a signal only where an interpolation
		reads one in plain sight, with `.get()`; one that calls a function which reads signals is wrapped in this.
	**/
	public static function live(f:Void->String):Computed<String>
		return Computed.make(f);

	/** `el` as a button: a press on it calls `act`. It takes the pointer's hand and focus. **/
	public static function press(el:Element, act:Void->Void):Element {
		ashui.input.Interaction.of(el.node).setFocusable(true).onClick(_ -> act());
		Identity.of(el.tree, el.node.id).addClasses(["dash-press"]);
		return el;
	}
}
