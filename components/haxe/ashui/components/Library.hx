package ashui.components;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.ui.Div;

/**
	Provides styled components built from Ashui's core elements.
	Add `-lib ashui-components` and import the components you use. Importing
	`Button`, for example, makes `<button>` resolve to the library component.

	`components/css/components.css` loads when the first component is created.
	Application stylesheets take precedence. Components expose classes,
	attributes and states for styling:

	- Parts use `ui-*` classes, such as `ui-card-header` and `ui-switch-thumb`.
	- Variants, sizes and states use `data-*` attributes and pseudo-classes,
	  such as `[data-size="sm"]`, `[data-state="active"]` and `:hover`.
	- Custom properties allow local overrides. For example,
	  `--ui-button-bg` overrides the fallback `--primary` color for buttons
	  in that subtree without requiring a stronger selector.

	Colors, motion, radii and shadows use the active theme's tokens.
**/
class Library {
	static var used = false;

	/**
		Loads `components/css/components.css` below application stylesheets.
		Components call this automatically; the stylesheet is built only once.
	**/
	public static function use():Void {
		if (used)
			return;
		used = true;
		ashui.css.Css.useLibrary("ashui-components", ashui.css.CompiledCss.file("../../../css/components.css"));
	}

	/**
		Creates a named component part styled by its class. For example,
		`part("ui-drawer-handle")` creates an element styled by `.ui-drawer-handle`.

		`tag` defaults to `div`. The element receives `name` and any extra `classes`.
		`data` entries become `data-*` attributes. Values can be constants,
		signals or computeds; null omits the attribute. `children` are placed inside.
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
