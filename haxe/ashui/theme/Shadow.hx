package ashui.theme;

/** One layer of a theme shadow. **/
@:structInit
final class Shadow {
	public final offsetX:Float;
	public final offsetY:Float;
	public final blur:Float;
	public final spread:Float;
	public final color:Rgba;

	public function new(offsetX:Float, offsetY:Float, blur:Float, spread:Float, color:Rgba) {
		this.offsetX = F32.round(offsetX);
		this.offsetY = F32.round(offsetY);
		this.blur = F32.round(blur);
		this.spread = F32.round(spread);
		this.color = color;
	}

	/** No shadow: zero everywhere, transparent. **/
	public static function none():Shadow {
		return new Shadow(0, 0, 0, 0, Rgba.TRANSPARENT);
	}

	/** From `from` to `to` by `t`; the offsets, blur and spread are not clamped, the colour is. **/
	public static function lerp(from:Shadow, to:Shadow, t:Float):Shadow {
		return new Shadow(from.offsetX + (to.offsetX - from.offsetX) * t, from.offsetY + (to.offsetY - from.offsetY) * t,
			from.blur + (to.blur - from.blur) * t, from.spread + (to.spread - from.spread) * t, Rgba.lerp(from.color, to.color, t));
	}

	/** Two stacks layer by layer, the shorter padded with `none()`. **/
	public static function lerpStack(from:Array<Shadow>, to:Array<Shadow>, t:Float):Array<Shadow> {
		var n = Std.int(Math.max(from.length, to.length));
		return [
			for (i in 0...n)
				lerp(i < from.length ? from[i] : none(), i < to.length ? to[i] : none(), t)
		];
	}

	/** This layer for a node. **/
	public function toShadow():ashui.types.Shadow {
		return new ashui.types.Shadow(offsetX, offsetY, blur, color.rgb(), color.a, spread);
	}

	/** A whole stack for a node, in order; null for an empty stack, which sets no shadow. **/
	public static function toShadowStack(stack:Array<Shadow>):Null<ashui.types.Shadow> {
		if (stack.length == 0)
			return null;
		var shadow = stack[0].toShadow();
		for (i in 1...stack.length) {
			var layer = stack[i];
			shadow.and(layer.offsetX, layer.offsetY, layer.blur, layer.color.rgb(), layer.color.a, layer.spread);
		}
		return shadow;
	}
}
