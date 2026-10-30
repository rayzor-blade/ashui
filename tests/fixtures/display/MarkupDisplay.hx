import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/** Display requests inside inline markup, which tests/run.sh asks at the markers below. **/
class MarkupDisplay {
	static function main() {
		var count = Signal.make(2);
		var names = ["a", "b"];
		Owner.root(new LayoutTree(), _ -> <div width={count.}><for {n in names}><text>{n.}</text></for><text>{count}</text></div>);
		Owner.root(new LayoutTree(), _ -> <div class="x" ></div>);
		Owner.root(new LayoutTree(), _ -> <spa></spa>);
		Owner.root(new LayoutTree(), _ -> <display-card headline="a" ></display-card>);
	}
}

/** A component, whose props an attribute list completes. **/
class DisplayCard extends ashui.ui.Component<{headline:String, ?expanded:Bool}> {
	function render():ashui.layout.Element
		return new ashui.ui.Div({});
}
