import ashui.ui.View;

// A template expression starting to call a standard library static,
// Math.round. ashui already calls it, so the reload adds no field to Math's
// class; a static nothing in the program used before would be refused.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={Math.round(count * 10.4)} height={8}>
			<text>v6 ${count}</text>
		</div>
	';

	public function version():String
		return "v6";
}
