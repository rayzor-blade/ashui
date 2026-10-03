package ashui.core.render;

/**
	The first pass of a layer's drop shadow: each fragment over the layer's
	bounds is the Gaussian average of the layer's alpha along its row,
	`gradient.z` pixels of deviation, written as it is into the shadow
	texture, which `LayerShader` blurs down the columns, offsets and tints.
**/
class LayerShadowShader implements UiShader {
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
			var sigma = primitive.gradient.z;
			var size = textureSize(layer);
			var alpha = layer.fetch(ivec2(int(fragCoord.x), int(fragCoord.y))).a;
			if (sigma > 0.25) {
				// Two texels a read, as in LayerBlurShader.
				var reach = ceil(sigma * 3.);
				var sum = 0.;
				var weights = 0.;
				var i = -reach;
				while (i <= reach) {
					var w0 = exp(-i * i / (2. * sigma * sigma));
					var w1 = exp(-(i + 1.) * (i + 1.) / (2. * sigma * sigma));
					var w = w0 + w1;
					sum += textureLod(layer, vec2(fragCoord.x + i + w1 / w, fragCoord.y) / size, 0.).a * w;
					weights += w;
					i += 2.;
				}
				alpha = sum / weights;
			}
			output.color = vec4(0., 0., 0., alpha);
		}
	};
}
