package ashui.draw3d;

import ashui.math.Vec3;

/**
	A light in a 3D scene. Colours are `0xRRGGBB`, as `Brush` takes them;
	`intensity` scales them, 1 lighting a surface facing it fully.
**/
enum Light {
	/** From far away, all one way, as the sun: `direction` is the way it travels. **/
	Directional(direction:Vec3, color:Int, intensity:Float);

	/** From a point, fading to nothing at `range`. **/
	Point(position:Vec3, color:Int, intensity:Float, range:Float);

	/** From a point along `direction`, full inside `inner` radians of it and nothing past `outer`. **/
	Spot(position:Vec3, direction:Vec3, color:Int, intensity:Float, range:Float, inner:Float, outer:Float);
}
