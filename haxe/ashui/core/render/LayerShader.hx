package ashui.core.render;

/**
	A layer, a group drawn offscreen (see `Renderer`), composited back: its
	quad covers the bounds of what was drawn into the layer, and each
	fragment reads the layer's texel under it. The
	layer holds colour premultiplied by alpha, as drawing into a cleared
	target with the UI blend leaves it, so the colour is divided out again
	and the alpha multiplied by the group's opacity, `color.a`; the usual
	blend then composites it. The colour goes through the group's colour
	filter on the way, a 3 × 4 matrix in the `color2`, `border` and
	`borderColor` rows: the identity when it has none. With a blur of
	`color.r` pixels of deviation, `layer` is `LayerBlurShader`'s rows
	already blurred, and this blurs its columns. With a drop shadow, a
	colour `via` of any alpha, the content goes over it: `shadow` is
	`LayerShadowShader`'s alpha blurred along its rows, which this blurs
	down its columns at the shadow's offset, `gradient.xy` pixels.
**/
class LayerShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;
		@param var shadow : Sampler2D;

		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			var b = primitive.bounds;
			var pixel = placed(b.xy, primitive.affine, quadCorner(vertexID) * b.zw);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			// The layer is the target's size, so the fragment's position is its texel.
			var x = int(fragCoord.x);
			var y0 = int(fragCoord.y);
			var texel = layer.fetch(ivec2(x, y0));
			var sigma = primitive.color.x;
			if (sigma > 0.) {
				var last = int(textureSize(layer).y) - 1;
				var reach = int(ceil(sigma * 3.));
				var step = max(1, int(sigma / 6.));
				var sum = vec4(0., 0., 0., 0.);
				var weights = 0.;
				var i = -reach;
				while (i <= reach) {
					var y = y0 + i;
					if (y < 0)
						y = 0;
					if (y > last)
						y = last;
					var d = float(i);
					var w = exp(-d * d / (2. * sigma * sigma));
					sum += layer.fetch(ivec2(x, y)) * w;
					weights += w;
					i += step;
				}
				texel = sum / weights;
			}
			var rgb = vec3(0., 0., 0.);
			if (texel.a > 0.0001)
				rgb = texel.rgb / texel.a;
			var c = vec4(rgb, 1.);
			rgb = clamp(vec3(dot(primitive.color2, c), dot(primitive.border, c), dot(primitive.borderColor, c)), vec3(0., 0., 0.), vec3(1., 1., 1.));
			var a = texel.a;
			var tint = primitive.via;
			if (tint.a > 0.) {
				// The shadow's alpha at the offset, blurred down its column; its rows were blurred already.
				var sx = x - int(floor(primitive.gradient.x + 0.5));
				var sy0 = y0 - int(floor(primitive.gradient.y + 0.5));
				var size = textureSize(shadow);
				var fallen = 0.;
				if (sx >= 0 && sx < int(size.x)) {
					var sigma2 = max(primitive.gradient.z, 0.0001);
					var last = int(size.y) - 1;
					var reach = int(ceil(sigma2 * 3.));
					var step = max(1, int(sigma2 / 6.));
					var sum = 0.;
					var weights = 0.;
					var i = -reach;
					while (i <= reach) {
						var sy = sy0 + i;
						if (sy < 0)
							sy = 0;
						if (sy > last)
							sy = last;
						var d = float(i);
						var w = exp(-d * d / (2. * sigma2 * sigma2));
						sum += shadow.fetch(ivec2(sx, sy)).a * w;
						weights += w;
						i += step;
					}
					fallen = sum / weights;
				}
				// The content over its shadow, in premultiplied colour, then straight again.
				var sa = fallen * tint.a;
				var outA = a + sa * (1. - a);
				var premult = rgb * a + tint.rgb * sa * (1. - a);
				rgb = vec3(0., 0., 0.);
				if (outA > 0.0001)
					rgb = premult / outA;
				a = outA;
			}
			output.color = vec4(rgb, a * primitive.color.a);
		}
	};
}
