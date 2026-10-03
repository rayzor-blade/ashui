// expect: tw: bg-primary/150: an opacity is 0 to 100
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class TwOpacityRange {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 h-10 bg-primary/150" />'));
	}
}
