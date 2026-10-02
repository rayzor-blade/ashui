import ashui.ui.View;

class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<Div width={count * 10} height={8}>
			<Text>v1 ${count}</Text>
		</Div>
	';

	public function version():String
		return "v1";
}
