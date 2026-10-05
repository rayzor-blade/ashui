// expect: broken.css:2: characters 12-13 : css: ::after is not supported; ::placeholder is
// A sheet compiled by CompiledCss reports its errors at their place in the CSS file, as a compile error.
class CssCompiledError {
	static function main() {
		var sheet = ashui.css.CompiledCss.file("../css/broken.css");
	}
}
