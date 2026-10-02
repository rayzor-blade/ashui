import ashui.ui.View;

// Same methods and fields as v1: only bodies change.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<Div width={count * 20} height={8}>
			<Text>v2 ${count}</Text>
		</Div>
	';

	public function version():String
		return "v2";
}
