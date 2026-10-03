// expect: svg: "chartreuse" is not a colour ashui knows
import ashui.svg.SvgDocument;

class SvgInlineMarkup {
	static function main() {
		SvgDocument.of(<svg viewBox="0 0 2 2"><rect width="2" height="2" fill="chartreuse"/></svg>);
	}
}
