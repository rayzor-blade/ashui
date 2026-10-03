// expect: hxx: <div> has no attribute "widht"
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxUnknownAttribute {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div widht={10} />'));
	}
}
