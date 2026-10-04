package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Div;

/**
	ashui.components: composed components in the manner of shadcn/ui, on
	ashui's built-in elements, for an app to take or leave. Add the library
	with `--class-path components/haxe` and import what you use; an
	imported `Button` is `<button>` in hxx, in place of the built-in.

	Every look is CSS, in `components/css/components.css`, which is put in
	force under the page's own sheets the first time a component is made,
	so a page's CSS restyles any of it the way it restyles built-in
	elements. Components set classes, attributes and states, never a look of
	their own, which would win over the page's CSS:

	- each part has a class, `ui-` and its name: `ui-card`, `ui-card-header`,
	  `ui-switch-thumb`;
	- variants, sizes and states are attributes and pseudo-classes:
	  `[data-variant="outline"]`, `[data-size="sm"]`, `[data-state="active"]`,
	  `:hover`, `:checked`, `:disabled`, `:focus-visible`;
	- each component reads its own custom properties, falling back to the
	  theme's tokens, `background: var(--ui-button-bg, var(--primary))`, so
	  setting `--ui-button-bg` on any element above retunes the buttons
	  inside it without a selector to outrank.

	Motion, radii, colours and shadows are the theme's tokens, as the
	user-agent stylesheet's are.
**/
class Library {
	/** The library's stylesheet, read from `components/css/components.css` when the program is compiled. **/
	public static final CSS:String = Sheet.read();

	/** Puts the library's stylesheet in force, once, under the page's sheets. **/
	public static function use():Void
		ashui.css.Css.useLibrary("ashui-components", CSS);

	/**
		A part's element: a box of HTML type `tag` (`div` unless given), of
		class `name` and any `classes` after it, its `data-` attributes from
		`data`, each a constant or a signal or computed it follows (null
		leaves it out), holding `children`.
	**/
	public static function part(name:String, ?tag:String, ?data:Map<String, IntoReactive<Null<String>>>, ?children:Array<Element>, ?id:String,
			?classes:Array<String>):Div {
		use();
		var box = new Div({tag: tag, id: id, classes: [name].concat(classes == null ? [] : classes)}, children);
		if (data != null) {
			var identity = ashui.css.Identity.of(box.tree, box.node.id);
			for (key => value in data)
				identity.bindAttribute("data-" + key, value);
		}
		return box;
	}
}
