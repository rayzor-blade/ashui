package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

typedef CardProps = {
	?id:String
}

/**
	A raised surface that groups related content.
	Compose a `CardHeader` with `CardTitle` and `CardDescription`, followed by
	`CardContent` and `CardFooter`. CSS parts use `.ui-card` and the suffixes
	`-header`, `-title`, `-description`, `-content`, and `-footer`. Variables:
	`--ui-card-bg`, `-fg`, `-border`, `-radius`, `-padding`, `-gap`, `-shadow`.
**/
class Card extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card", null, null, children, props.id);
}

/** Card header containing a title and description. **/
class CardHeader extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-header", null, null, children, props.id);
}

/** Title text for a card. **/
class CardTitle extends Component<CardProps> {
	function render():Element {
		var box = Library.part("ui-card-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Supporting text below the card title. **/
class CardDescription extends Component<CardProps> {
	function render():Element {
		var box = Library.part("ui-card-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Main content of a card. **/
class CardContent extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-content", null, null, children, props.id);
}

/** Card footer for actions. **/
class CardFooter extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-footer", null, null, children, props.id);
}
