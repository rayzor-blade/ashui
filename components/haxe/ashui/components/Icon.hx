package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	An SVG icon, such as `<icon document={Icons.PLAY_LINE} class="size-5"/>`.

	Accepts an `IconSet` document, `SvgDocument.of(<svg>...</svg>)`, or SVG
	markup. Icons using `currentColor` inherit the surrounding text color
	and respond to utilities such as `text-primary`. CSS controls size with
	classes such as `size-5` or `w-6 h-6`; otherwise the document size is used.
	The element exposes `.ui-icon`.
**/
class Icon extends Component<{document:ashui.svg.Icon, ?id:String}> {
	function render():Element {
		var svg = new ashui.ui.Svg(props.document);
		var identity = ashui.css.Identity.of(svg.tree, svg.node.id).addClasses(["ui-icon"]);
		if (props.id != null)
			identity.setId(props.id);
		return svg;
	}
}
