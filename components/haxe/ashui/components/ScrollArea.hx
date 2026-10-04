package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef ScrollAreaProps = {
	/** When its scrollbar shows: "auto" while it scrolls (the default), "always", "hover" or "hidden". **/
	?scrollbars:String,
	/** Which ways it scrolls: "vertical" (the default), "horizontal" or "both". **/
	?orientation:String,
	?id:String
}

/**
	A box its content scrolls in, under the wheel or a trackpad, a thin
	thumb showing how far along it is; size it with the element's own width
	and height. CSS: `.ui-scroll-area` (`[data-scrollbars]`,
	`[data-orientation]`), which sets `overflow` and `scrollbar-visibility`.
**/
class ScrollArea extends Component<ScrollAreaProps> {
	function render():Element
		return Library.part("ui-scroll-area", null, [
			"scrollbars" => (props.scrollbars == null ? "auto" : props.scrollbars),
			"orientation" => (props.orientation == null ? "vertical" : props.orientation)
		], children, props.id);
}
