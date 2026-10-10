import ashui.ui.View;

// Adds a reactive attribute: its computed is a new function, which a reload
// adds to the running program.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={count * 20} height={count * 2}>
			<text>v3 ${count}</text>
		</div>
	';

	public function version():String
		return "v3";
}
