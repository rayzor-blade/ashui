package ashui.core.render;

/**
	A layer composited back: its quad covers the bounds of what was drawn
	into the layer, and each fragment reads the layer's texel under it. The
	layer holds colour premultiplied by alpha, as drawing into a cleared
	target with the UI blend leaves it, so the colour is divided out again
	and the alpha multiplied by the group's opacity, `color.a`; the usual
	blend then composites it. The colour goes through the group's colour
	filter on the way, a 3 × 4 matrix in the `color2`, `border` and
	`borderColor` rows: the identity when it has none.
**/
class LayerShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			var b = primitive.bounds;
			var pixel = placed(b.xy, primitive.affine, quadCorner(vertexID) * b.zw);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			// The layer is the target's size, so the fragment's position is its texel.
			var texel = layer.fetch(ivec2(int(fragCoord.x), int(fragCoord.y)));
			var rgb = vec3(0., 0., 0.);
			if (texel.a > 0.0001)
				rgb = texel.rgb / texel.a;
			var c = vec4(rgb, 1.);
			rgb = clamp(vec3(dot(primitive.color2, c), dot(primitive.border, c), dot(primitive.borderColor, c)), vec3(0., 0., 0.), vec3(1., 1., 1.));
			output.color = vec4(rgb, texel.a * primitive.color.a);
		}
	};
}
