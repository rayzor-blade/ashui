// expect: ashui.ui.Div should be ashui.ui.Text
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;
import ashui.ui.Ref;

class HxxRefWrongType {
	static function main() {
		var label = new Ref<ashui.ui.Text>();
		Owner.root(new LayoutTree(), _ -> hxx('<div ref={label} />'));
	}
}
