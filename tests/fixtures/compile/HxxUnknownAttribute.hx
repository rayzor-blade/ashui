// expect: hxx: Div has no attribute "widht"
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxUnknownAttribute {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<Div widht={10} />'));
	}
}
