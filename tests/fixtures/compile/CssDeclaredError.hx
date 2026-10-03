// expect: broken.css:2: characters 12-13 : css: ::after is not supported; ::placeholder is
// flags: -D ashui_css=fixtures/css/broken.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssDeclaredError {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 ok" />'));
	}
}
