package ashui.layout;

/** A node's laid-out rectangle, in absolute coordinates. **/
class Bounds {
	public var x(default, null):Single;
	public var y(default, null):Single;
	public var width(default, null):Single;
	public var height(default, null):Single;

	public function new(x:Single, y:Single, width:Single, height:Single) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
	}

	public function toString():String {
		return 'Bounds($x, $y, $width, $height)';
	}
}
