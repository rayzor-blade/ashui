package ashui.core.render;

/**
	A box: its fill, solid or a gradient of up to three stops, with its
	border drawn inside its edge, its corners shaped as its record says,
	under its clip. Edge, corners and border all come from the box's signed
	distance (see `Sdf`), so they stay smooth under any transform. Ported
	from the rect branch of Blinc's `sdf_core.wgsl`.
**/
class BoxShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		var output : { position : Vec4, color : Vec4 };
		/**
			Where the fragment is in the box's own coordinates, from its top-left,
			for the shape and fill (`xy`), and on screen, for the clip (`zw`).
			Values passed between stages are few, so pairs share a vec4.
		**/
		var place : Vec4;
		/** The box's size; its fill type plus four times its clips; its clips' corner `n`. **/
		var box : Vec4;

		/**
			The fill at `p`: `fillType` 0 is solid, 1 linear from `g.xy` to
			`g.zw`, 2 radial at `g.xy` of radius `g.z`. A gradient runs from `c1`
			at `stops.x` to `c2` at `stops.z`, through `via` at `stops.y` when
			`stops.w` is 1.
		**/
		function fillAt(p : Vec2, c1 : Vec4, c2 : Vec4, via : Vec4, stops : Vec4, g : Vec4, fillType : Float) : Vec4 {
			var c = c1;
			if (fillType > 0.5) {
				var t = 0.;
				if (fillType < 1.5) {
					var dir = g.zw - g.xy;
					t = dot(p - g.xy, dir) / dot(dir, dir);
				} else {
					t = length(p - g.xy) / g.z;
				}
				if (stops.w > 0.5) {
					if (t <= stops.y)
						c = mix(c1, via, clamp((t - stops.x) / max(stops.y - stops.x, 0.0001), 0., 1.));
					else
						c = mix(via, c2, clamp((t - stops.y) / max(stops.z - stops.y, 0.0001), 0., 1.));
				} else {
					c = mix(c1, c2, clamp((t - stops.x) / max(stops.z - stops.x, 0.0001), 0., 1.));
				}
			}
			return c;
		}

		/**
			`fill` with the border composited over it where `p` is in the ring
			between the edge and the inner shape; straight alpha. With
			different side widths the inner corners are quarter ellipses. Each
			side has its colour; a point takes the side it is nearest for that
			side's width, so two sides meet on the line from the outer corner to
			the inner one, as CSS joins them.
		**/
		function withBorder(p : Vec2, origin : Vec2, size : Vec2, radii : Vec4, shape : Vec4, d : Float, coverage : Float, fill : Vec4,
				border : Vec4, topColor : Vec4, rightColor : Vec4, bottomColor : Vec4, leftColor : Vec4, aa : Float) : Vec4 {
			var result = fill;
			if (max(max(border.x, border.y), max(border.z, border.w)) > 0.) {
				// Each side its own: ashui writes all four, a uniform border as four equal widths.
				var top = border.x;
				var right = border.y;
				var bottom = border.z;
				var left = border.w;
				var halfSize = size * 0.5;
				var rel = p - (origin + halfSize);
				var borderColor = topColor;
				var nearest = (rel.y + halfSize.y) / max(top, 0.0001);
				var toRight = (halfSize.x - rel.x) / max(right, 0.0001);
				if (toRight < nearest) {
					nearest = toRight;
					borderColor = rightColor;
				}
				var toBottom = (halfSize.y - rel.y) / max(bottom, 0.0001);
				if (toBottom < nearest) {
					nearest = toBottom;
					borderColor = bottomColor;
				}
				if ((rel.x + halfSize.x) / max(left, 0.0001) < nearest)
					borderColor = leftColor;
				var r = radii.w;
				var n = shape.w;
				if (rel.y < 0.) {
					r = radii.x;
					n = shape.x;
					if (rel.x > 0.) {
						r = radii.y;
						n = shape.y;
					}
				} else if (rel.x > 0.) {
					r = radii.z;
					n = shape.z;
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
				// A concave corner's edges lie inside the box and away from its corner square.
				var concave = n < 0.;
				if (nearCorner || !insideStraight || concave) {
					var innerSdf = 0.;
					if (abs(reduced.x - reduced.y) < 0.001 || concave)
						innerSdf = -(d + reduced.x);
					else if (cornerCenterToPoint.x <= 0. || cornerCenterToPoint.y <= 0.)
						innerSdf = -max(straightInner.x, straightInner.y);
					else if (abs(n - 1.) < 0.01)
						innerSdf = quarterEllipseSdf(cornerCenterToPoint, max(vec2(0., 0.), vec2(r, r) - reduced));
					else {
						// The inner corner of a squircle border: a superellipse of the reduced radii.
						var innerRadii = max(vec2(0., 0.), vec2(r, r) - reduced);
						var e = pow(2., min(abs(n), 5.));
						if (min(innerRadii.x, innerRadii.y) < 0.001) {
							innerSdf = -length(max(vec2(0., 0.), cornerCenterToPoint));
						} else {
							var it = cornerCenterToPoint / innerRadii;
							var se = pow(max(it.x, 0.), e) + pow(max(it.y, 0.), e);
							innerSdf = -((pow(se, 1. / e) - 1.) * sqrt(innerRadii.x * innerRadii.y));
						}
					}
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
			// The quad reaches a pixel and a half past the box, so the edge's
			// anti-aliasing is not cut off where a transform turns the edge.
			var m = primitive.affine;
			var grow = vec2(1.5, 1.5) / max(vec2(length(m.xy), length(m.zw)), vec2(0.01, 0.01));
			var local = quadCorner(vertexID) * (b.zw + grow * 2.) - grow;
			var pixel = placed(b.xy, primitive.affine, local);
			place = vec4(local, pixel);
			box = vec4(b.zw, primitive.typeInfo.y + 4. * primitive.typeInfo.z, primitive.typeInfo.w);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			// Half a screen pixel in the box's own units, which a transform scales or slants;
			// taken before the discard, as derivatives need every fragment of the quad.
			var local = place.xy;
			var aa = halfPixel(local);
			var clips = floor(box.z * 0.25);
			var fillType = box.z - 4. * clips;
			var clip = clipCoverage(place.zw, primitive.clipBounds, primitive.clipRadius, clips, box.w)
				* localClipCoverage(local, primitive.shadow, primitive.shadowColor, clips, box.w, aa)
				* fadeCoverage(place.zw, primitive.fadeBounds, primitive.fade)
				* shapeCoverage(place.zw);
			if (clip < 0.001)
				discard;
			var p = local;
			var origin = vec2(0., 0.);
			var size = box.xy;
			var d = boxDistance(p, size, primitive.cornerRadius, primitive.cornerShape, primitive.notchCorners, primitive.notchTop, primitive.notchBottom);
			var notched = isNotch(primitive.notchCorners, primitive.notchTop, primitive.notchBottom);
			var coverage = 1. - smoothstep(-aa, aa, d);
			if (coverage < 0.001)
				discard;
			var fill = fillAt(p, primitive.color, primitive.color2, primitive.via, primitive.stops, primitive.gradient, fillType);
			if (notched) {
				// A notch's border follows its outline. Where the sides differ, its body's edges split it as a box's do: a flare
				// beside the body is the top's or the bottom's, and elsewhere the nearest edge for its width takes the point,
				// so a modifier at the top or bottom is that side's.
				var width = primitive.border.x;
				var color = primitive.borderTop;
				var b = primitive.border;
				// How much of the band a point beside the body keeps: within its side's width of that side's edge.
				var keep = 1.;
				var differ = abs(b.y - b.x) + abs(b.z - b.x) + abs(b.w - b.x) + length(primitive.borderRight - color)
					+ length(primitive.borderBottom - color) + length(primitive.borderLeft - color);
				if (differ > 0.0001) {
					var body = notchBody(size, primitive.notchCorners, primitive.notchTop, primitive.notchBottom);
					var half = body.zw * 0.5;
					var rel = p - (body.xy + half);
					var side = 0;
					if (abs(rel.x) > half.x) {
						if (rel.y > 0.)
							side = 2;
					} else {
						var nearest = (rel.y + half.y) / max(b.x, 0.0001);
						var toRight = (half.x - rel.x) / max(b.y, 0.0001);
						if (toRight < nearest) {
							nearest = toRight;
							side = 1;
						}
						var toBottom = (half.y - rel.y) / max(b.z, 0.0001);
						if (toBottom < nearest) {
							nearest = toBottom;
							side = 2;
						}
						if ((rel.x + half.x) / max(b.w, 0.0001) < nearest)
							side = 3;
					}
					var own = rel.y + half.y;
					if (side == 1) {
						width = b.y;
						color = primitive.borderRight;
						own = half.x - rel.x;
					} else if (side == 2) {
						width = b.z;
						color = primitive.borderBottom;
						own = half.y - rel.y;
					} else if (side == 3) {
						width = b.w;
						color = primitive.borderLeft;
						own = rel.x + half.x;
					}
					// A scoop or cut carved into the top or bottom is that side's over its whole span.
					var carve = vec4(0., 0., 0., 0.);
					if (side == 0)
						carve = primitive.notchTop;
					else if (side == 2)
						carve = primitive.notchBottom;
					var carved = (carve.x > 0.5 && carve.x < 1.5) || (carve.x > 2.5 && carve.x < 3.5);
					var over = carved && abs(p.x - size.x * 0.5) <= carve.y * 0.5 + width;
					if (abs(rel.x) <= half.x && !over)
						keep = smoothstep(-aa, aa, width - own);
				}
				if (width > 0.) {
					var ring = smoothstep(-aa, aa, d + width) * keep;
					fill = mix(fill, vec4(color.rgb, color.a), ring * color.a);
				}
			} else
				fill = withBorder(p, origin, size, primitive.cornerRadius, primitive.cornerShape, d, coverage, fill, primitive.border,
					primitive.borderTop, primitive.borderRight, primitive.borderBottom, primitive.borderLeft, aa);
			output.color = vec4(fill.rgb, fill.a * clip * coverage);
		}
	};
}
