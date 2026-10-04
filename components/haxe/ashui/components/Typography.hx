package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

/**
	Long-form text: the HTML elements inside it, headings, paragraphs,
	quotations, lists, inline code, tables and rules, set for reading, with
	the space between them coming from what they are rather than from
	margins of their own. It is no wider than a comfortable line by
	default. CSS: `.ui-prose`; `--ui-prose-width`.
**/
class Prose extends Component<{?id:String}> {
	function render():Element {
		Library.use();
		return Library.part("ui-prose", null, null, children, props.id);
	}
}

/** The paragraph that opens a piece, larger and quieter than the text after it. CSS: `.ui-lead`. **/
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

/** Text a size up and heavier, for a short statement that stands out. CSS: `.ui-large`. **/
class Large extends Component<{?id:String}> {
	function render():Element
		return Lead.flow("ui-large", children, props.id);
}

/** Smaller, quieter text, for what comments on what is around it. CSS: `.ui-muted`. **/
class Muted extends Component<{?id:String}> {
	function render():Element
		return Lead.flow("ui-muted", children, props.id);
}
