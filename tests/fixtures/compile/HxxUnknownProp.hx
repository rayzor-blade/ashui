// expect: hxx: <label> has no prop "colour"
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Component;
import ashui.ui.Hxx.hxx;
import ashui.ui.Text;

class Label extends Component<{text:IntoReactive<String>}> {
	function render():Element
		return new Text(props.text);
}

class HxxUnknownProp {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<label text={"x"} colour={1} />'));
	}
}
