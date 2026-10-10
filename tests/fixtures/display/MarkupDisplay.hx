import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/** Display requests inside inline markup, which tests/run.sh asks at the markers below. **/
class MarkupDisplay {
	static function main() {
		var count = Signal.make(2);
		var names = ["a", "b"];
		Owner.root(new LayoutTree(), _ -> <div width={count.}><for {n in names}><text>{n.}</text></for><text>{count}</text></div>);
	}
}
