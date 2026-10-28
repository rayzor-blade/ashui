package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.ui.Component;

typedef BreadcrumbProps = {
	/** Separator text, such as `/` or `→`. Defaults to a chevron. **/
	?separator:String,
	?size:Size,
	?id:String
}

/**
	A navigation path ending at the current page.
	Use `BreadcrumbItem` for each level and set `current={true}` on the last
	item. Separators appear between items. CSS: `.ui-breadcrumb`, `[data-size]`,
	`.ui-breadcrumb-item`, `[data-current]`, `:hover`, and `.ui-breadcrumb-separator`.
**/
class Breadcrumb extends Component<BreadcrumbProps> {
	static var chevron:Null<ashui.svg.SvgDocument> = null;

	function render():Element {
		var parts:Array<Element> = [];
		for (i => c in children) {
			if (i > 0)
				parts.push(separator());
			parts.push(c);
		}
		return Library.part("ui-breadcrumb", "nav", ["size" => (props.size == null ? Size.Md : props.size : String)], parts, props.id);
	}

	function separator():Element {
		if (props.separator != null)
			return Library.part("ui-breadcrumb-separator", null, null, [new ashui.ui.Text(props.separator)]);
		if (chevron == null)
			chevron = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>);
		var icon = new ashui.ui.Svg(chevron, {width: 14, height: 14});
		return Library.part("ui-breadcrumb-separator", null, null, [icon]);
	}
}

/** A link to a parent page, or the current page in a breadcrumb. **/
class BreadcrumbItem extends Component<{?current:Bool, ?onClick:ashui.input.Events.PointerEvent->Void, ?id:String}> {
	function render():Element {
		var box = Library.part("ui-breadcrumb-item", props.current == true ? null : "a", props.current == true ? ["current" => "page"] : null, children,
			props.id);
		ashui.text.InlineFlow.attach(box);
		if (props.current != true) {
			var i = Interaction.of(box.node).setFocusable(true);
			if (props.onClick != null)
				i.onClick(props.onClick);
		}
		return box;
	}
}
