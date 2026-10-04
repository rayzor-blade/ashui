package ashui.components;

import ashui.ui.Component;
import ashui.layout.Element;

typedef CardProps = {
	?id:String
}

/**
	A card: a raised surface for related content, its parts `CardHeader`
	(holding `CardTitle` and `CardDescription`), `CardContent` and
	`CardFooter`. CSS: `.ui-card`, `.ui-card-header`, `.ui-card-title`,
	`.ui-card-description`, `.ui-card-content`, `.ui-card-footer`;
	`--ui-card-bg`, `-fg`, `-border`, `-radius`, `-padding`, `-gap`,
	`-shadow`.
**/
class Card extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card", null, null, children, props.id);
}

/** A card's header: its title and description. **/
class CardHeader extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-header", null, null, children, props.id);
}

/** A card's title, a flow of text. **/
class CardTitle extends Component<CardProps> {
	function render():Element {
		var box = Library.part("ui-card-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** A card's description, under its title, a flow of text. **/
class CardDescription extends Component<CardProps> {
	function render():Element {
		var box = Library.part("ui-card-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** A card's content. **/
class CardContent extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-content", null, null, children, props.id);
}

/** A card's footer: its actions. **/
class CardFooter extends Component<CardProps> {
	function render():Element
		return Library.part("ui-card-footer", null, null, children, props.id);
}
