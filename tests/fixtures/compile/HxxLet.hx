// expect: hxx: <let> and <switch> are not supported
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxLet {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<div><let w={10}><div width={w} /></let></div>'));
	}
}
