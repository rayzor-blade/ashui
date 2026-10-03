// expect: tw: [clip-path:circle(10)]: "10" needs a unit, px or %
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class TwClipPathUnit {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 h-10 [clip-path:circle(10)]" />'));
	}
}
