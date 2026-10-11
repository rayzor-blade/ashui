// expect: broken.css:2: characters 14-15 : css: ::made-up is not supported; use ::before, ::after or ::placeholder
// A sheet compiled by CompiledCss reports its errors at their place in the CSS file, as a compile error.
class CssCompiledError {
	static function main() {
		var sheet = ashui.css.CompiledCss.file("../css/broken.css");
	}
}
