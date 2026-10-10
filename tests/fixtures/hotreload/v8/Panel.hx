import ashui.ui.View;

// Gains a @:state field: a field and its get_ and set_ methods added to a running class.
// The existing count keeps its value; the new step starts at its default.
class Panel extends View {
	@:state public var count:Int = 1;
	@:state public var step:Int = 3;

	function render() '
		<div width={count * step} height={8}>
			<text>v8 ${count}</text>
		</div>
	';

	public function version():String
		return "v8";
}
