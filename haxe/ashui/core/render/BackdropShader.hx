package ashui.core.render;

/**
	A backdrop filter drawn: over the element's box, what was drawn behind
	it, `layer` already blurred along its rows by `BackdropRowsShader`,
	blurred down its columns (`color.r` pixels of deviation) and through the
	colour filter in the `color2`, `border` and `borderColor` rows, covering
	the element's rounded box under its clips. The element's own fill and
	content are drawn over it next.
**/
class BackdropShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var place : Vec4;

		function vertex() {
			var b = primitive.bounds;
			var m = primitive.affine;
			var grow = vec2(1.5, 1.5) / max(vec2(length(m.xy), length(m.zw)), vec2(0.01, 0.01));
			var local = quadCorner(vertexID) * (b.zw + grow * 2.) - grow;
			var pixel = placed(b.xy, m, local);
			place = vec4(local, pixel);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var local = place.xy;
			var aa = halfPixel(local);
			var clips = primitive.typeInfo.z;
			var n = primitive.typeInfo.w;
			var cover = (1. - smoothstep(-aa, aa, sdShapedRect(local, vec2(0., 0.), primitive.bounds.zw, primitive.cornerRadius, primitive.cornerShape)))
				* clipCoverage(place.zw, primitive.clipBounds, primitive.clipRadius, clips, n)
				* localClipCoverage(local, primitive.shadow, primitive.shadowColor, clips, n, aa)
				* fadeCoverage(place.zw, primitive.fadeBounds, primitive.fade)
				* shapeCoverage(place.zw);
			if (cover < 0.001)
				discard;
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
				sum += textureLod(layer, vec2(fragCoord.x, fragCoord.y + i + w1 / w) / size, 0.) * w;
				weights += w;
				i += 2.;
			}
			var texel = sum / weights;
			var rgb = vec3(0., 0., 0.);
			if (texel.a > 0.0001)
				rgb = texel.rgb / texel.a;
			var c = vec4(rgb, 1.);
			rgb = clamp(vec3(dot(primitive.color2, c), dot(primitive.border, c), dot(primitive.borderColor, c)), vec3(0., 0., 0.), vec3(1., 1., 1.));
			output.color = vec4(rgb, texel.a * cover);
		}
	};
}
