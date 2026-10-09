package ashui.core.render;

/**
	A box shadow, as CSS's `box-shadow`: the box offset and grown by the
	spread, blurred by a Gaussian, drawn outside the box only, under its
	clip. The blur is worked out per pixel from the box's signed distance
	with the error function, so it needs no blur pass. An inset one, fill
	type 1, is drawn inside the box instead, where the box offset and shrunk
	by the spread does not cover: its box is the padding box, so the border
	stays over it. Ported from Blinc's `sdf_shadow.wgsl`.
**/
class ShadowShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		var local : Vec2;

		function vertex() {
			var s = primitive.shadow;
			var grow = s.z * 3. + abs(s.x) + abs(s.y) + max(s.w, 0.) + 1.;
			var b = primitive.bounds;
			local = quadCorner(vertexID) * (b.zw + vec2(grow, grow) * 2.) - vec2(grow, grow);
			pixel = placed(b.xy, primitive.affine, local);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var clip = clipCoverage(pixel, primitive.clipBounds, primitive.clipRadius, primitive.typeInfo.z, primitive.typeInfo.w)
				* fadeCoverage(pixel, primitive.fadeBounds, primitive.fade)
				* shapeCoverage(pixel);
			if (clip < 0.001)
				discard;
			var p = local;
			var origin = vec2(0., 0.);
			var size = primitive.bounds.zw;
			var s = primitive.shadow;
			var result = vec4(0., 0., 0., 0.);
			// Outside the box for an outer shadow, inside it for an inset one.
			var where = smoothstep(-0.75, 0.75, boxDistance(p, size, primitive.cornerRadius, primitive.cornerShape, primitive.notchCorners, primitive.notchTop, primitive.notchBottom));
			var notched = isNotch(primitive.notchCorners, primitive.notchTop, primitive.notchBottom);
			if (primitive.typeInfo.y > 0.5) {
				// Where the box offset and shrunk by the spread leaves off, its edge blurred.
				var spread = vec2(s.w, s.w);
				var inner = 0.;
				// A notch's outline moved by the offset and drawn in by the spread.
				if (notched)
					inner = sdNotch(p - s.xy, size, primitive.notchCorners, primitive.notchTop, primitive.notchBottom) + s.w;
				else
					inner = sdShapedRect(p, origin + s.xy + spread, max(size - spread * 2., vec2(0., 0.)),
						max(primitive.cornerRadius - vec4(s.w, s.w, s.w, s.w), vec4(0., 0., 0., 0.)), primitive.cornerShape);
				var shade = 0.;
				// No blur: a hard edge, antialiased over a pixel.
				if (s.z < 0.001) {
					shade = clamp(0.5 + inner, 0., 1.);
				} else {
					shade = 0.5 * (1. + erf(inner / (0.5 * sqrt(2.) * s.z)));
				}
				result = primitive.shadowColor * shade;
				where = 1. - where;
			} else {
				var spread = vec2(s.w, s.w);
				var d = 0.;
				if (notched)
					d = sdNotch(p - s.xy, size, primitive.notchCorners, primitive.notchTop, primitive.notchBottom) - s.w;
				else {
					// CSS's spread radius: a corner grows by the spread as far as it is already round, so a square one stays square.
					var r = primitive.cornerRadius;
					var grown = max(r + vec4(s.w, s.w, s.w, s.w), vec4(0., 0., 0., 0.));
					if (s.w > 0.) {
						var u = min(r / s.w, vec4(1., 1., 1., 1.)) - vec4(1., 1., 1., 1.);
						grown = r + (vec4(1., 1., 1., 1.) + u * u * u) * s.w;
					}
					d = sdShapedRect(p, origin + s.xy - spread, size + spread * 2., grown, primitive.cornerShape);
				}
				var alpha = 0.;
				if (s.z < 0.001) {
					alpha = clamp(0.5 - d, 0., 1.);
				} else {
					alpha = 0.5 * (1. + erf(-d / (0.5 * sqrt(2.) * s.z)));
				}
				result = primitive.shadowColor * alpha;
			}
			output.color = vec4(result.rgb, result.a * where * clip);
		}
	};
}
