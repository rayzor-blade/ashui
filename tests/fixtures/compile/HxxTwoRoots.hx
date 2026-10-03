// expect: hxx: a template has exactly one root element
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxTwoRoots {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div /><div />'));
	}
}
