import ashui.ui.View;

// Adds a reactive attribute: its computed is a new function, so this is not
// a body-only change. Ash does not support it; the fixture shows what happens.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<Div width={count * 20} height={count * 2}>
			<Text>v3 ${count}</Text>
		</Div>
	';

	public function version():String
		return "v3";
}
