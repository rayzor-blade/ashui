package ashui.ui;

import ashui.layout.Element;

/** HTML's `<summary>`: the heading of a `<details>`, which toggles it; a marker before its content turns as it opens. **/
class Summary extends Component<{}> {
	static final MARKER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>';

	function render():Element {
		var marker = new Svg(ashui.svg.SvgDocument.parse(MARKER), {width: 12, height: 12});
		ashui.css.Identity.of(marker.tree, marker.node.id).setClasses(["marker"]);
		var box = new Div({tag: "summary"}, ([marker] : Array<Element>).concat(children));
		ashui.input.Interaction.of(box.node).setFocusable(true);
		return box;
	}
}
