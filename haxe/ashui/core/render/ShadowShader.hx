package ashui.core.render;

/**
	A box shadow: a Gaussian of the box offset and spread, drawn outside the
	box only, under its clip. Blinc's `sdf_shadow.wgsl` for shadow primitives.
**/
class ShadowShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		var local : Vec2;

		function vertex() {
			var s = primitive.shadow;
			var grow = s.z * 3. + abs(s.x) + abs(s.y);
			var b = primitive.bounds;
			local = quadCorner(vertexID) * (b.zw + vec2(grow, grow) * 2.) - vec2(grow, grow);
			pixel = placed(b.xy, primitive.affine, local);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var clip = clipCoverage(pixel, primitive.clipBounds, primitive.clipRadius, primitive.typeInfo.z, primitive.typeInfo.w)
				* fadeCoverage(pixel, primitive.fadeBounds, primitive.fade);
			if (clip < 0.001)
				discard;
			var p = local;
			var origin = vec2(0., 0.);
			var size = primitive.bounds.zw;
			var s = primitive.shadow;
			var result = vec4(0., 0., 0., 0.);
			if (s.z > 0. || s.w != 0.) {
				var spread = vec2(s.w, s.w);
				var d = sdShapedRect(p, origin + s.xy - spread, size + spread * 2., primitive.cornerRadius + vec4(s.w, s.w, s.w, s.w),
					primitive.cornerShape);
				var alpha = 0.;
				if (s.z < 0.001) {
					if (d < 0.)
						alpha = 1.;
				} else {
					alpha = 0.5 * (1. + erf(-d / (0.5 * sqrt(2.) * s.z)));
				}
				result = primitive.shadowColor * alpha;
			}
			var outside = smoothstep(-0.75, 0.75, sdShapedRect(p, origin, size, primitive.cornerRadius, primitive.cornerShape));
			output.color = vec4(result.rgb, result.a * outside * clip);
		}
	};
}
