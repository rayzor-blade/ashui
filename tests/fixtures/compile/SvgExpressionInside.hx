// expect: hxx: inside <svg>, "d" takes only a quoted value
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class SvgExpressionInside {
	static function main() {
		var d = "M0 0h4v4z";
		Owner.root(new LayoutTree(), _ -> hxx('<svg viewBox="0 0 24 24"><path d={d}/></svg>'));
	}
}
