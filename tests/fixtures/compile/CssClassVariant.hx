// expect: tw: hover:card: a variant takes Tw classes; for a CSS class, write .card:hover in the stylesheet
// flags: -D ashui_css=fixtures/css/smoke.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssClassVariant {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 hover:card" />'));
	}
}
