import ashui.ui.View;

// Body-only change, but the string literals change length ("v1" -> "version four").
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={count * 20} height={8}>
			<text>version four ${count}</text>
		</div>
	';

	public function version():String
		return "version four";
}
