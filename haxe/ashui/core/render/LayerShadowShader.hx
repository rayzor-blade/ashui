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
			var last = int(textureSize(layer).x) - 1;
			var x0 = int(fragCoord.x);
			var y = int(fragCoord.y);
			var alpha = layer.fetch(ivec2(x0, y)).a;
			if (sigma > 0.25) {
				var reach = int(ceil(sigma * 3.));
				var step = max(1, int(sigma / 6.));
				var sum = 0.;
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
					sum += layer.fetch(ivec2(x, y)).a * w;
					weights += w;
					i += step;
				}
				alpha = sum / weights;
			}
			output.color = vec4(0., 0., 0., alpha);
		}
	};
}
