import ashui.ui.View;

class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={count * 10} height={8}>
			<text>v1 ${count}</text>
		</div>
	';

	public function version():String
		return "v1";
}
