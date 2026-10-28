package ashui.components;

import ashui.layout.Element;
import ashui.ui.Component;

typedef ScrollAreaProps = {
	/** Scrollbar visibility: `auto` while scrolling (default), `always`, `hover`, or `hidden`. **/
	?scrollbars:String,
	/** Scroll direction: `vertical` (default), `horizontal`, or `both`. **/
	?orientation:String,
	?id:String
}

/**
	A scrollable container with wheel and trackpad support.
	Set width and height to define the visible area. A thin scrollbar thumb
	shows scroll position. CSS: `.ui-scroll-area` with `[data-scrollbars]`
	and `[data-orientation]`, controlling `overflow` and `scrollbar-visibility`.
**/
class ScrollArea extends Component<ScrollAreaProps> {
	function render():Element
		return Library.part("ui-scroll-area", null, [
			"scrollbars" => (props.scrollbars == null ? "auto" : props.scrollbars),
			"orientation" => (props.orientation == null ? "vertical" : props.orientation)
		], children, props.id);
}
