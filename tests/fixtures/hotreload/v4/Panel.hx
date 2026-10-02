import ashui.ui.View;

// Body-only change, but the string literals change length ("v1" -> "version four").
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<Div width={count * 20} height={8}>
			<Text>version four ${count}</Text>
		</Div>
	';

	public function version():String
		return "version four";
}
