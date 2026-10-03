// expect: @:state count needs an initial value
import ashui.ui.View;

class Counter extends View {
	@:state var count:Int;

	function render() '<div />';
}

class StateNeedsInitialValue {
	static function main() {}
}
