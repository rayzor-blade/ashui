// expect: broken.css:2: characters 5-6 : css: attribute selectors are not supported
// flags: -D ashui_css=fixtures/css/broken.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssDeclaredError {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 ok" />'));
	}
}
