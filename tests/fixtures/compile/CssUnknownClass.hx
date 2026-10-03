// expect: tw: unknown class crad; did you mean card?, or a class of the CSS in -D ashui_css
// flags: -D ashui_css=fixtures/css/smoke.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssUnknownClass {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 crad" />'));
	}
}
