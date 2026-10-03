// expect: imported.css:2: characters 15-16 : css: attribute selectors are not supported
// flags: -D ashui_css=fixtures/css/importer.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssImportedError {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 from-import own" />'));
	}
}
