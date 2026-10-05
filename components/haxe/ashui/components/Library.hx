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
	static var used = false;

	/**
		Puts the library's stylesheet, `components/css/components.css`, in
		force under the page's sheets. Every component calls this when it is
		made; only the first call builds the sheet, and later calls return at
		once.
	**/
	public static function use():Void {
		if (used)
			return;
		used = true;
		ashui.css.Css.useLibrary("ashui-components", ashui.css.CompiledCss.file("../../../css/components.css"));
	}

	/**
		Makes one of a component's inner elements, which the stylesheet styles
		by class. For example, a drawer's handle is
		`part("ui-drawer-handle")`, and `components.css` gives
		`.ui-drawer-handle` its look.

		The element is a `div` unless `tag` names another HTML element. Its
		classes are `name` followed by any `classes`. Each entry in `data`
		becomes a `data-` attribute that CSS can select on, such as
		`data-state="open"`. A value can be a constant, or a signal or
		computed that the attribute follows; null leaves the attribute out.
		`children` go inside it.
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
