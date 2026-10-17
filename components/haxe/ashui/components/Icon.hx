package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	An SVG icon in a template: `<icon document={Icons.PLAY_LINE} class="size-5"/>`.

	It takes a compiled document, from an `ashui.svg.IconSet` or
	`SvgDocument.of(<svg>...</svg>)`, or SVG markup in a string. An icon drawn
	in `currentColor` takes the colour of the text it is in, so `text-primary`
	on it or around it tints it. Its size is the document's, unless CSS gives
	it one: `size-5`, `w-6 h-6`. It has the class `ui-icon`.
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
