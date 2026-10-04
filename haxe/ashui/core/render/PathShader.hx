package ashui.core.render;

/**
	A canvas's drawing: triangles from the canvas's own data texture, read
	by vertex index, each vertex two texels: its position in layout units,
	its coverage and the texel where its paint starts; then its distances
	inside up to four edges of its shape, in pixels, which cover the pixels
	just inside an edge by how far inside they are. A paint is eight
	texels: its kind (0 solid, 1 linear, 2 radial), stop count and
	opacity; its geometry, in layout units; up to four stop offsets; and
	the stops' colours. Gradients are mixed premultiplied, as CSS mixes
	them. Drawn with the canvas's record as its instance, it is clipped as
	the canvas is (`canvasClip`).
**/
class PathShader implements UiShader {
	/** Texels to a row of the canvas's data texture. **/
	public static inline var ROW_TEXELS = 2048;

	/** Texels to a paint. **/
	public static inline var PAINT_TEXELS = 8;

	/** Texels to a vertex. **/
	public static inline var VERTEX_TEXELS = 2;

	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var canvas : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		var coverage : Float;
		var paint : Float;
		var edges : Vec4;

		function canvasTexel(t : Int) : Vec4 {
			return canvas.fetch(ivec2(t % 2048, t / 2048));
		}

		function vertex() {
			var v = canvasTexel(vertexID * 2);
			pixel = v.xy;
			coverage = v.z;
			paint = v.w;
			edges = canvasTexel(vertexID * 2 + 1);
			output.position = pixelToClip(pixel, viewport);
		}

		function premultiplied(c : Vec4) : Vec4 {
			return vec4(c.rgb * c.a, c.a);
		}

		function fragment() {
			var at = int(paint + 0.5);
			var head = canvasTexel(at);
			var color = canvasTexel(at + 3);
			if (head.x > 0.5) {
				var geo = canvasTexel(at + 1);
				var offsets = canvasTexel(at + 2);
				var t = 0.;
				if (head.x < 1.5) {
					var d = geo.zw - geo.xy;
					t = dot(pixel - geo.xy, d) / max(dot(d, d), 0.000001);
				} else {
					t = length(pixel - geo.xy) / max(geo.z, 0.000001);
				}
				t = clamp(t, 0., 1.);
				var p0 = premultiplied(canvasTexel(at + 3));
				var p1 = premultiplied(canvasTexel(at + 4));
				var p2 = premultiplied(canvasTexel(at + 5));
				var p3 = premultiplied(canvasTexel(at + 6));
				var mixed = p0;
				if (head.y > 1.5 && t > offsets.x)
					mixed = mix(p0, p1, clamp((t - offsets.x) / max(offsets.y - offsets.x, 0.000001), 0., 1.));
				if (head.y > 2.5 && t > offsets.y)
					mixed = mix(p1, p2, clamp((t - offsets.y) / max(offsets.z - offsets.y, 0.000001), 0., 1.));
				if (head.y > 3.5 && t > offsets.z)
					mixed = mix(p2, p3, clamp((t - offsets.z) / max(offsets.w - offsets.z, 0.000001), 0., 1.));
				color = mixed.a > 0.000001 ? vec4(mixed.rgb / mixed.a, mixed.a) : vec4(0., 0., 0., 0.);
			}
			// Inside each edge by half a pixel or more, fully covered; on the edge, half.
			var inside = clamp(edges + vec4(0.5, 0.5, 0.5, 0.5), vec4(0., 0., 0., 0.), vec4(1., 1., 1., 1.));
			var covered = coverage * inside.x * inside.y * inside.z * inside.w;
			output.color = vec4(color.rgb, color.a * head.z * covered * canvasClip(pixel));
		}
	};
}
