package ashui.core.render;

/**
	The first pass of a layer's blur: each fragment over the layer's
	bounds, grown by the blur, is the Gaussian average of the layer's row
	around it, `color.r` pixels of deviation. Its colour stays premultiplied
	and is written as it is, blending off, into the second texture, which
	`LayerShader` blurs down the columns as it composites.
**/
class LayerBlurShader implements UiShader {
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
			var sigma = max(primitive.color.x, 0.0001);
			var last = int(textureSize(layer).x) - 1;
			var x0 = int(fragCoord.x);
			var y = int(fragCoord.y);
			// Three deviations each side, in at most about forty steps.
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
