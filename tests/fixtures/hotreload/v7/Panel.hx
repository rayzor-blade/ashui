import ashui.ui.View;

// Gains a private helper method its own render calls: a method added to a running class.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={widthFor(count)} height={8}>
			<text>v7 ${count}</text>
		</div>
	';

	function widthFor(n:Int):Int
		return n * 12;

	public function version():String
		return "v7";
}
