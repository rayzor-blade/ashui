package ashui.core.render;

/**
	The first pass of a backdrop filter: over the element's box on screen,
	grown by `color.y` units for the column pass to read, each fragment is
	the Gaussian average of the target along its row, `color.r` pixels of
	deviation, written as it is into the target's second texture.
**/
class BackdropRowsShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };

		function vertex() {
			var b = primitive.bounds;
			var m = primitive.affine;
			// The box's corners on screen, then their bounds, grown.
			var c0 = placed(b.xy, m, vec2(0., 0.));
			var c1 = placed(b.xy, m, vec2(b.z, 0.));
			var c2 = placed(b.xy, m, vec2(0., b.w));
			var c3 = placed(b.xy, m, b.zw);
			var lo = min(min(c0, c1), min(c2, c3)) - vec2(primitive.color.y, primitive.color.y);
			var hi = max(max(c0, c1), max(c2, c3)) + vec2(primitive.color.y, primitive.color.y);
			output.position = pixelToClip(mix(lo, hi, quadCorner(vertexID)), viewport);
		}

		function fragment() {
			var size = textureSize(layer);
			var sigma = max(primitive.color.x, 0.0001);
			// Texels three deviations each side, two at a time: one filtered read between
			// a pair, at the ratio of their weights, is their weighted sum.
			var reach = ceil(sigma * 3.);
			var sum = vec4(0., 0., 0., 0.);
			var weights = 0.;
			var i = -reach;
			while (i <= reach) {
				var w0 = exp(-i * i / (2. * sigma * sigma));
				var w1 = exp(-(i + 1.) * (i + 1.) / (2. * sigma * sigma));
				var w = w0 + w1;
				sum += textureLod(layer, vec2(fragCoord.x + i + w1 / w, fragCoord.y) / size, 0.) * w;
				weights += w;
				i += 2.;
			}
			output.color = sum / weights;
		}
	};
}
