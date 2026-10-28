package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	A reading layout for long-form content.
	Styles headings, paragraphs, quotations, lists, code, tables, and rules
	with consistent spacing and a limited line width.
	CSS: `.ui-prose` and `--ui-prose-width`.
**/
class Prose extends Component<{?id:String}> {
	function render():Element {
		Library.use();
		return Library.part("ui-prose", null, null, children, props.id);
	}
}

/** Introductory paragraph with larger, muted text. CSS: `.ui-lead`. **/
class Lead extends Component<{?id:String}> {
	function render():Element
		return flow("ui-lead", children, props.id);

	@:allow(ashui.components)
	static function flow(cls:String, children:Array<Element>, id:Null<String>):Element {
		Library.use();
		var box = Library.part(cls, null, null, children, id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Larger, heavier text for a short prominent statement. CSS: `.ui-large`. **/
class Large extends Component<{?id:String}> {
	function render():Element
		return Lead.flow("ui-large", children, props.id);
}

/** Smaller, muted text for supporting information. CSS: `.ui-muted`. **/
class Muted extends Component<{?id:String}> {
	function render():Element
		return Lead.flow("ui-muted", children, props.id);
}
