// expect: ashui.types.Brush should be ashui.layout.IntoReactive<Single>
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Brush;

class TypedKeyMismatch {
	static function main() {
		new LayoutTree().createNode().set(Prop.Width, Brush.solid(0xff0000));
	}
}
