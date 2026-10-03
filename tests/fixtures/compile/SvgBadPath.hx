// expect: an arc flag is 0 or 1
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class SvgBadPath {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<svg viewBox="0 0 24 24"><path d="M0 0 A1 1 0 2 1 4 4"/></svg>'));
	}
}
