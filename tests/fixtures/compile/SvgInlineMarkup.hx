// expect: svg: the root element is not <svg>
import ashui.svg.SvgDocument;

class SvgInlineMarkup {
	static function main() {
		SvgDocument.of(<g><rect width="2" height="2"/></g>);
	}
}
