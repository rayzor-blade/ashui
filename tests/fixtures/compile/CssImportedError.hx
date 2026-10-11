// expect: imported.css:2: characters 24-25 : css: ::made-up is not supported; use ::before, ::after or ::placeholder
// flags: -D ashui_css=fixtures/css/importer.css
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class CssImportedError {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 from-import own" />'));
	}
}
