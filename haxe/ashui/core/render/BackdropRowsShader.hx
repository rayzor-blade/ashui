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
			var sigma = max(primitive.color.x, 0.0001);
			var last = int(textureSize(layer).x) - 1;
			var x0 = int(fragCoord.x);
			var y = int(fragCoord.y);
			var reach = int(ceil(sigma * 3.));
			var step = max(1, int(sigma / 6.));
			var sum = vec4(0., 0., 0., 0.);
			var weights = 0.;
			var i = -reach;
			while (i <= reach) {
				var x = x0 + i;
				if (x < 0)
					x = 0;
				if (x > last)
					x = last;
				var d = float(i);
				var w = exp(-d * d / (2. * sigma * sigma));
				sum += layer.fetch(ivec2(x, y)) * w;
				weights += w;
				i += step;
			}
			output.color = sum / weights;
		}
	};
}
