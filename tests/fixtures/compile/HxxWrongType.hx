// expect: ashui.types.Brush should be ashui.layout.IntoReactive<Single>
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;
import ashui.ui.Hxx.hxx;

class HxxWrongType {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<Div width={Brush.solid(1)} />'));
	}
}
