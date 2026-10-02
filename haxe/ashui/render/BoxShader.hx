package ashui.render;

/**
	A box: its fill, solid or a two-stop gradient, with its border drawn
	inside its edge, under its clip. Blinc's `sdf_core.wgsl` for rect
	primitives, without transforms or corner shapes.
**/
class BoxShader implements UiShader {
	static var SRC = {
		@:import ashui.render.Sdf;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;

		/** The fill at `p`: `fillType` 0 is solid, 1 linear from `g.xy` to `g.zw`, 2 radial at `g.xy` of radius `g.z`. **/
		function fillAt(p : Vec2, c1 : Vec4, c2 : Vec4, g : Vec4, fillType : Float) : Vec4 {
			var c = c1;
			if (fillType > 0.5 && fillType < 1.5) {
				var dir = g.zw - g.xy;
				c = mix(c1, c2, clamp(dot(p - g.xy, dir) / dot(dir, dir), 0., 1.));
			} else if (fillType > 1.5) {
				c = mix(c1, c2, clamp(length(p - g.xy) / g.z, 0., 1.));
			}
			return c;
		}

		/**
			`fill` with the border composited over it where `p` is in the ring
			between the edge and the inner shape; straight alpha. With
			different side widths the inner corners are quarter ellipses.
		**/
		function withBorder(p : Vec2, origin : Vec2, size : Vec2, radii : Vec4, d : Float, coverage : Float, fill : Vec4, border : Vec4,
				borderColor : Vec4) : Vec4 {
			var result = fill;
			if (max(max(border.x, border.y), max(border.z, border.w)) > 0.) {
				var aa = 0.5;
				var top = border.x;
				var right = border.x;
				var bottom = border.x;
				var left = border.x;
				if (border.y > 0. || border.z > 0. || border.w > 0.) {
					right = border.y;
					bottom = border.z;
					left = border.w;
				}
				var halfSize = size * 0.5;
				var rel = p - (origin + halfSize);
				var r = radii.w;
				if (rel.y < 0.) {
					r = radii.x;
					if (rel.x > 0.)
						r = radii.y;
				} else if (rel.x > 0.) {
					r = radii.z;
				}
				r = min(r, min(halfSize.x, halfSize.y));
				var bx = right;
				if (rel.x < 0.)
					bx = left;
				var by = bottom;
				if (rel.y < 0.)
					by = top;
				if (bx == 0.)
					bx = -aa;
				if (by == 0.)
					by = -aa;
				var reduced = vec2(bx, by);
				var cornerToPoint = abs(rel) - halfSize;
				var cornerCenterToPoint = cornerToPoint + vec2(r, r);
				var nearCorner = cornerCenterToPoint.x >= 0. && cornerCenterToPoint.y >= 0.;
				var straightInner = cornerToPoint + reduced;
				var insideStraight = straightInner.x < -aa && straightInner.y < -aa;
				if (nearCorner || !insideStraight) {
					var innerSdf = 0.;
					if (abs(reduced.x - reduced.y) < 0.001)
						innerSdf = -(d + reduced.x);
					else if (cornerCenterToPoint.x <= 0. || cornerCenterToPoint.y <= 0.)
						innerSdf = -max(straightInner.x, straightInner.y);
					else
						innerSdf = quarterEllipseSdf(cornerCenterToPoint, max(vec2(0., 0.), vec2(r, r) - reduced));
					var borderA = borderColor.a * smoothstep(-aa, aa, -innerSdf) * step(0.001, coverage);
					var outA = borderA + fill.a * (1. - borderA);
					var rgb = vec3(0., 0., 0.);
					if (outA >= 0.0001)
						rgb = (borderColor.rgb * borderA + fill.rgb * fill.a * (1. - borderA)) / outA;
					result = vec4(rgb, outA);
				}
			}
			return result;
		}

		function vertex() {
			var b = primitive.bounds;
			pixel = b.xy + quadCorner(vertexID) * b.zw;
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var p = pixel;
			var clip = clipCoverage(p, primitive.clipBounds, primitive.clipRadius, primitive.typeInfo.z);
			if (clip < 0.001)
				discard;
			var origin = primitive.bounds.xy;
			var size = primitive.bounds.zw;
			var d = sdRoundedRect(p, origin, size, primitive.cornerRadius);
			var coverage = 1. - smoothstep(-0.5, 0.5, d);
			var fill = fillAt(p, primitive.color, primitive.color2, primitive.gradient, primitive.typeInfo.y);
			fill = withBorder(p, origin, size, primitive.cornerRadius, d, coverage, fill, primitive.border, primitive.borderColor);
			output.color = vec4(fill.rgb, fill.a * clip * coverage);
		}
	};
}
