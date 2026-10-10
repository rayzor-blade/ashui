import ashui.types.Style;
import ashui.ui.View;

// Adds a child component, Chip, a class the running program does not have.
class Panel extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={count * 10} flexDirection={Column}>
			<div height={8} />
			<chip />
		</div>
	';

	public function version():String
		return "v5";
}
