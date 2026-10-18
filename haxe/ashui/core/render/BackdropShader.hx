package ashui.core.render;

/**
	A backdrop filter drawn: over the element's box, what was drawn behind
	it, `layer` already blurred along its rows by `BackdropRowsShader`,
	blurred down its columns (`color.r` pixels of deviation) and through the
	colour filter in the `color2`, `border` and `borderColor` rows, covering
	the element's rounded box under its clips. The element's own fill and
	content are drawn over it next.

	Where nothing is drawn behind it, as in a transparent window over the
	desktop, it draws the tint the filter adds over what shows through,
	which the system blurs when the window asks it to. The result is faded
	by the element's opacity, `color.w`. A glass's grain, `color.z`, adds
	Blinc's smooth value noise over the result.

	Liquid glass, `gradient.x` 1, has a lens at its rim and is
	`LiquidBackdropShader`'s: this one is the filter alone.
**/
class BackdropShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;
		@param var layer:Sampler2D;
		var output:{position:Vec4, color:Vec4};
		/** A pseudo-random value in [0, 1) for each cell of the plane. **/
		function hash(p:Vec2):Float {
			return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
		}
		/** Value noise: the cells' hashes, smoothly interpolated. **/
		function noise(p:Vec2):Float {
			var i = floor(p);
			var f = fract(p);
			var u = f * f * (3. - 2. * f);
			return mix(mix(hash(i), hash(i + vec2(1., 0.)), u.x), mix(hash(i + vec2(0., 1.)), hash(i + vec2(1., 1.)), u.x), u.y);
		}
		var place:Vec4;
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
			var box = primitive.bounds.zw;
			var radius = primitive.cornerRadius;
			var shape = primitive.cornerShape;
			var nc = primitive.notchCorners;
			var nt = primitive.notchTop;
			var nb = primitive.notchBottom;
			var d = boxDistance(local, box, radius, shape, nc, nt, nb);
			var cover = (1. - smoothstep(-aa, aa,
				d)) * clipCoverage(place.zw, primitive.clipBounds, primitive.clipRadius, clips,
					n) * localClipCoverage(local, primitive.shadow, primitive.shadowColor, clips, n,
					aa) * fadeCoverage(place.zw, primitive.fadeBounds, primitive.fade) * shapeCoverage(place.zw);
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
				var at = vec2(fragCoord.x, fragCoord.y + i + w1 / w);
				sum += textureLod(layer, at / size, 0.) * w;
				weights += w;
				i += 2.;
			}
			var texel = sum / weights;
			var rgb = vec3(0., 0., 0.);
			if (texel.a > 0.0001)
				rgb = texel.rgb / texel.a;
			var c = vec4(rgb, 1.);
			rgb = clamp(vec3(dot(primitive.color2, c), dot(primitive.border, c), dot(primitive.borderColor, c)), vec3(0., 0., 0.), vec3(1., 1., 1.));
			// Where nothing is drawn behind it, as in a transparent window, what shows through is the desktop, which the
			// system blurs: over it, the tint the filter adds, premultiplied, at the alpha it covers what is behind with.
			var tint = clamp(vec3(primitive.color2.w, primitive.border.w, primitive.borderColor.w), vec3(0., 0., 0.), vec3(1., 1., 1.));
			var tintAlpha = clamp(1. - (primitive.color2.x + primitive.border.y + primitive.borderColor.z) / 3., 0., 1.);
			// What is drawn behind it, filtered, and the desktop's share where nothing is.
			var under = texel.a;
			var alpha = under + tintAlpha * (1. - under);
			if (alpha > 0.0001)
				rgb = (rgb * under + tint * (1. - under)) / alpha;
			if (primitive.color.z > 0.) {
				var grain = (noise(place.zw * 0.3) - 0.5) * primitive.color.z * 0.02;
				rgb = clamp(rgb + vec3(grain, grain, grain), vec3(0., 0., 0.), vec3(1., 1., 1.));
			}
			output.color = vec4(rgb, alpha * cover * primitive.color.w);
		}
	};
}
