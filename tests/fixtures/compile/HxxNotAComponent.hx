// expect: hxx: <LayoutTree> is not an ashui.ui.Component
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxNotAComponent {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<LayoutTree />'));
	}
}
