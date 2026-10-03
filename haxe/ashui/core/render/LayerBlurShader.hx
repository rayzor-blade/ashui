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
