package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.ui.Component;

typedef BreadcrumbProps = {
	/** Text between the items, as "/" or "→"; a chevron by default. **/
	?separator:String,
	?size:Size,
	?id:String
}

/**
	Where a page sits, a path of `BreadcrumbItem`s, links back up, ending
	in the current page (`current={true}`), with a separator between each.
	CSS: `.ui-breadcrumb` (`[data-size]`), `.ui-breadcrumb-item`
	(`[data-current]`, `:hover`), `.ui-breadcrumb-separator`.
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

/** One step of a breadcrumb: a link up, or the current page. **/
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
