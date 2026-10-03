// expect: svg: <linearGradient> is not supported yet
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class SvgUnsupported {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<svg viewBox="0 0 24 24"><linearGradient id="g"/><rect width="4" height="4"/></svg>'));
	}
}
