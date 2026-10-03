// expect: tw: a state variant of the background would replace the backdrop blur; vary something else
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class TwBackdropVariant {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div class="w-10 h-10 bg-white/30 hover:bg-white/50 backdrop-blur-md" />'));
	}
}
