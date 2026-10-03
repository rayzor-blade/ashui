// expect: hxx: tags are lowercase kebab-case: write <my-card>
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Hxx.hxx;

class HxxPascalTag {
	static function main() {
		Owner.root(new LayoutTree(), _ -> hxx('<MyCard />'));
	}
}
