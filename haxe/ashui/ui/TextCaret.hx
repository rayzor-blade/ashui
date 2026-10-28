package ashui.ui;

import ashui.input.WindowState;
import ashui.reactive.Watch;

/**
	Publishes the focused text caret to the window input method.

	`WindowState.textCaret` places IME candidates beside the caret. The caret
	is cleared when focus leaves the text view.
**/
class TextCaret {
	/**
		Publishes the window caret rectangle returned by `where` while `editing`
		is focused. When focus changes, only the previous publisher can clear
		its own rectangle.
	**/
	public static function publish(editing:TextEditing, where:Void->Null<ashui.input.WindowState.CaretArea>):Void {
		var mine:Null<ashui.input.WindowState.CaretArea> = null;
		new Watch(() -> editing.focused.get() ? where() : null, rect -> {
			if (rect != null) {
				mine = rect;
				WindowState.textCaret.set(rect);
			} else if (mine != null) {
				if (WindowState.textCaret.get() == mine)
					WindowState.textCaret.set(null);
				mine = null;
			}
		},
			(a, b) -> a == b || (a != null && b != null && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height));
	}
}
