// expect: MarkupWrongType.hx:9
// flags: --macro ashui.ui.Markup.enable()
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;

class MarkupWrongType {
	static function main() {
		Owner.root(new LayoutTree(), _ -> <div width={Brush.solid(1)} />);
	}
}
