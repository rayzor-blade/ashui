// expect: @:state count needs a type
import ashui.ui.View;

class Counter extends View {
	@:state var count = 0;

	function render() '<div />';
}

class StateNeedsType {
	static function main() {}
}
