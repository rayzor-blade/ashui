package ashui.ui;

import ashui.input.WindowState;
import ashui.reactive.Watch;

/**
	Tells the window where a focused text view's caret is, so it turns its
	input method on and shows the method's candidates beside the caret
	(`WindowState.textCaret`), and that there is none once focus leaves.
**/
class TextCaret {
	/**
		Publishes `editing`'s caret, at the window rect `where` gives, while
		it has focus. Moving focus between views hands the caret over: a view
		clears the signal only while it still holds that view's rect.
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
		}, (a, b) -> a == b || (a != null && b != null && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height));
	}
}
