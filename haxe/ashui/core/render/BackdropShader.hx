package ashui.core.render;

/**
	A backdrop filter drawn: over the element's box, what was drawn behind
	it, `layer` already blurred along its rows by `BackdropRowsShader`,
	blurred down its columns (`color.r` pixels of deviation) and through the
	colour filter in the `color2`, `border` and `borderColor` rows, covering
	the element's rounded box under its clips. The element's own fill and
	content are drawn over it next.

	Liquid glass, `gradient.x` 1, is Blinc's: within its rim, what is behind
	is read from further out along the edge's normal (`gradient.y` of the
	full 60 pixels), as a curved edge bends light; a thin line along the
	edge (`gradient.z` wide) catches light from the angle `gradient.w`, or is
	drawn in the top side's colour when that has any alpha; a faint shadow
	lies inside it; and a little of the tint in `via` is mixed over.
	`stops.x` separates red further out and blue further in along that
	normal, strongest at the edge and zero past the bevel. Zero keeps the
	three channels together; one separates each by 12% of the refraction.
	The rim's light separates by the same strength, including over a
	transparent window where there is no backdrop texture to refract.

	Where nothing is drawn behind it, as in a transparent window over the
	desktop, it draws the tint and the rim's light over what shows through,
	which the system blurs when the window asks it to. The result is faded
	by the element's opacity, `color.w`.

	A glass's grain, `color.z`, adds Blinc's smooth value noise over the
	result, finer on liquid glass than on frosted.
**/
class BackdropShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var layer : Sampler2D;

		var output : { position : Vec4, color : Vec4 };

		/** A pseudo-random value in [0, 1) for each cell of the plane. **/
		function hash(p : Vec2) : Float {
			return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
		}

		/** Value noise: the cells' hashes, smoothly interpolated. **/
		function noise(p : Vec2) : Float {
			var i = floor(p);
			var f = fract(p);
			var u = f * f * (3. - 2. * f);
			return mix(mix(hash(i), hash(i + vec2(1., 0.)), u.x), mix(hash(i + vec2(0., 1.)), hash(i + vec2(1., 1.)), u.x), u.y);
		}

		function rimLine(inner : Float, width : Float) : Float {
			return smoothstep(0., width * 0.3, inner) * (1. - smoothstep(width, width * 1.5, inner));
		}

		function rimLens(inner : Float, rim : Float) : Float {
			var bevel = 1. - clamp(inner / rim, 0., 1.);
			return bevel * bevel;
		}
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
			var box = primitive.bounds.zw;
			var radius = primitive.cornerRadius;
			var shape = primitive.cornerShape;
			var nc = primitive.notchCorners;
			var nt = primitive.notchTop;
			var nb = primitive.notchBottom;
			var d = boxDistance(local, box, radius, shape, nc, nt, nb);
			var cover = (1. - smoothstep(-aa, aa, d))
				* clipCoverage(place.zw, primitive.clipBounds, primitive.clipRadius, clips, n)
				* localClipCoverage(local, primitive.shadow, primitive.shadowColor, clips, n, aa)
				* fadeCoverage(place.zw, primitive.fadeBounds, primitive.fade)
				* shapeCoverage(place.zw);
			if (cover < 0.001)
				discard;
			var size = textureSize(layer);
			// Liquid glass's rim: the edge's normal on screen, and how far to read along it.
			var liquid = primitive.gradient.x > 0.5;
			var inner = max(0., -d);
			var normal = vec2(0., 0.);
			var offset = vec2(0., 0.);
			var lens = 0.;
			var rim = min(25., min(box.x, box.y) * 0.2);
			if (liquid) {
				var e = 0.5;
				var gx = boxDistance(local + vec2(e, 0.), box, radius, shape, nc, nt, nb) - boxDistance(local - vec2(e, 0.), box, radius, shape, nc, nt, nb);
				var gy = boxDistance(local + vec2(0., e), box, radius, shape, nc, nt, nb) - boxDistance(local - vec2(0., e), box, radius, shape, nc, nt, nb);
				var m = primitive.affine;
				var g = vec2(m.x * gx + m.z * gy, m.y * gx + m.w * gy);
				normal = g / max(length(g), 0.0001);
				lens = rimLens(inner, rim);
				// Layout units to target pixels.
				var k = size.x / viewport.x * length(m.xy);
				offset = normal * lens * 60. * primitive.gradient.y * k;
			}
			var sigma = max(primitive.color.x, 0.0001);
			var split = offset * (primitive.stops.x * 0.12);
			var disperse = dot(split, split) > 0.000001;
			// Texels three deviations each side, two at a time: one filtered read between
			// a pair, at the ratio of their weights, is their weighted sum.
			var reach = ceil(sigma * 3.);
			var sum = vec4(0., 0., 0., 0.);
			var red = vec2(0., 0.);
			var blue = vec2(0., 0.);
			var weights = 0.;
			var i = -reach;
			while (i <= reach) {
				var w0 = exp(-i * i / (2. * sigma * sigma));
				var w1 = exp(-(i + 1.) * (i + 1.) / (2. * sigma * sigma));
				var w = w0 + w1;
				var at = vec2(fragCoord.x + offset.x, fragCoord.y + offset.y + i + w1 / w);
				sum += textureLod(layer, at / size, 0.) * w;
				if (disperse) {
					var r = textureLod(layer, (at + split) / size, 0.);
					var b = textureLod(layer, (at - split) / size, 0.);
					red += vec2(r.r, r.a) * w;
					blue += vec2(b.b, b.a) * w;
				}
				weights += w;
				i += 2.;
			}
			var texel = sum / weights;
			if (disperse)
				texel = vec4(red.x, sum.g, blue.x, max(sum.a, max(red.y, blue.y))) / weights;
			var rgb = vec3(0., 0., 0.);
			if (texel.a > 0.0001)
				rgb = texel.rgb / texel.a;
			var c = vec4(rgb, 1.);
			rgb = clamp(vec3(dot(primitive.color2, c), dot(primitive.border, c), dot(primitive.borderColor, c)), vec3(0., 0., 0.), vec3(1., 1., 1.));
			// Where nothing is drawn behind it, as in a transparent window, what shows through is the desktop, which the
			// system blurs: over it, the tint the filter adds, premultiplied, at the alpha it covers what is behind with.
			var tint = clamp(vec3(primitive.color2.w, primitive.border.w, primitive.borderColor.w), vec3(0., 0., 0.), vec3(1., 1., 1.));
			var tintAlpha = clamp(1. - (primitive.color2.x + primitive.border.y + primitive.borderColor.z) / 3., 0., 1.);
			if (liquid) {
				var width = primitive.gradient.z;
				var line = rimLine(inner, width);
				var lightShift = primitive.stops.x * width * 0.75;
				var light = vec2(cos(primitive.gradient.w), sin(primitive.gradient.w));
				var litRgb = vec3(rimLine(inner + lightShift, width), line, rimLine(inner - lightShift, width))
					* (0.6 * (0.2 + 0.8 * max(0., dot(normal, -light))));
				var lit = max(litRgb.r, max(litRgb.g, litRgb.b));
				var edge = primitive.borderTop;
				var s0 = width * 2.5;
				var s1 = width * 8.;
				var shade = smoothstep(s0, s1, inner) * (1. - smoothstep(s1, s1 * 3., inner)) * 0.04;
				var via = primitive.via.a * 0.08;
				if (edge.a > 0.001) {
					rgb = mix(rgb, edge.rgb, line * edge.a);
					var k = line * edge.a;
					tint = tint * (1. - k) + edge.rgb * k;
					tintAlpha = k + tintAlpha * (1. - k);
				} else {
					rgb = rgb + litRgb;
					tint = tint * (1. - lit) + litRgb;
					tintAlpha = lit + tintAlpha * (1. - lit);
				}
				rgb = rgb - vec3(shade, shade, shade);
				rgb = clamp(mix(rgb, primitive.via.rgb, via), vec3(0., 0., 0.), vec3(1., 1., 1.));
				tint = tint * (1. - shade) * (1. - via) + primitive.via.rgb * via;
				tintAlpha = via + (shade + tintAlpha * (1. - shade)) * (1. - via);
				// With nothing behind it to bend, its rim is lit as a thick, curved edge is: darker just inside it, then light
				// gathered toward the edge, most where it faces the light and a weaker reflection across from there.
				var band = lens * (1. - lens) * 4. * 0.12;
				tint = tint * (1. - band);
				tintAlpha = band + tintAlpha * (1. - band);
				var specShift = primitive.stops.x * 3.;
				var spectrum = vec3(rimLens(inner + specShift, rim), lens, rimLens(inner - specShift, rim));
				var specRgb = spectrum * spectrum * (0.85 * max(0., dot(normal, -light)) + 0.35 * max(0., dot(normal, light)));
				var spec = max(specRgb.r, max(specRgb.g, specRgb.b));
				tint = tint * (1. - spec) + specRgb;
				tintAlpha = spec + tintAlpha * (1. - spec);
				// Enough of it that the system blurs what is behind even a clear one.
				tintAlpha = max(tintAlpha, 0.04);
			}
			// What is drawn behind it, filtered, and the desktop's share where nothing is.
			var under = texel.a;
			var alpha = under + tintAlpha * (1. - under);
			if (alpha > 0.0001)
				rgb = (rgb * under + tint * (1. - under)) / alpha;
			if (primitive.color.z > 0.) {
				var grain = (noise(place.zw * 0.3) - 0.5) * primitive.color.z * (liquid ? 0.005 : 0.02);
				rgb = clamp(rgb + vec3(grain, grain, grain), vec3(0., 0., 0.), vec3(1., 1., 1.));
			}
			output.color = vec4(rgb, alpha * cover * primitive.color.w);
		}
	};
}
