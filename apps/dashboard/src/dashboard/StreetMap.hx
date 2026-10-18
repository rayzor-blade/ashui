package dashboard;

import ashui.draw.DrawContext;
import ashui.draw.GlyphOutlines.TextAlignment;
import ashui.draw.GlyphOutlines.TextBaseline;
import ashui.draw.Path;
import ashui.draw.Stroke;
import ashui.types.Brush;

/** A map's colours. **/
private typedef MapStyle = {land:Int, building:Int, green:Int, water:Int, rail:Int, casing:Int, major:Int, minor:Int, service:Int, label:Int};

/**
	OpenStreetMap drawn on a canvas, as vectors: a street map extract
	(`assets/map/`, © OpenStreetMap contributors, ODbL) of polylines and
	polygons in metres, with a route and places marked on it. It draws in
	the page's scheme, parks, water and buildings under the streets, the
	route as a glowing line in the accent colour, the chargers as pins in the
	colour of how many of their chargers are free, and where the car is. The
	credit OpenStreetMap asks for sits in its corner.
**/
class StreetMap {
	static final LIGHT:MapStyle = {
		land: 0xeef1f5, building: 0xd6dde6, green: 0xd3ead7, water: 0xb9d8f6, rail: 0xb3bcc8,
		casing: 0xd0d7e0, major: 0xffffff, minor: 0xffffff, service: 0xf7f8fa, label: 0x6b7280
	};
	static final DARK:MapStyle = {
		land: 0x182030, building: 0x263043, green: 0x1a3026, water: 0x1b3453, rail: 0x394355,
		casing: 0x121824, major: 0x3d4a61, minor: 0x313d51, service: 0x283244, label: 0x8b95a7
	};

	final data:Dynamic;
	final car:Null<ashui.types.Bitmap>;

	/** The map at `path`, and the car drawn from above, nose up, at `carIcon`. **/
	public function new(path:String, ?carIcon:String) {
		data = haxe.Json.parse(ashui.core.Assets.text(path));
		car = carIcon == null ? null : ashui.types.Bitmap.load(carIcon);
	}

	/**
		Draws the map `w` by `h`, framed on the route, the chargers and the
		car with `margin` pixels round them, in the light or dark scheme, the
		route in `accent`. `free` gives each charger's colour; `flow`
		moves the light running along the route, in pixels.
	**/
	public function draw(ctx:DrawContext, w:Float, h:Float, margin:Float, light:Bool, accent:Int, free:Array<Int>, flow = 0.0, destination = 0, zoom = 1.0,
			guiding = true):Void {
		var style = light ? LIGHT : DARK;
		var marked:Array<Array<Float>> = (data.route : Array<Array<Float>>).concat([for (c in (data.places.chargers : Array<Dynamic>)) (c.at : Array<Float>)])
			.concat([(data.places.car : Array<Float>)]);
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (q in marked) {
			x0 = Math.min(x0, q[0]);
			x1 = Math.max(x1, q[0]);
			y0 = Math.min(y0, q[1]);
			y1 = Math.max(y1, q[1]);
		}
		var scale = Math.min((w - margin * 2) / (x1 - x0), (h - margin * 2) / (y1 - y0)) * zoom;
		var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
		inline function sx(x:Float):Float
			return (x - cx) * scale + w / 2;
		inline function sy(y:Float):Float
			return (y - cy) * scale + h / 2;
		function path(points:Array<Array<Float>>, closed:Bool):Path {
			var p = new Path();
			for (i => q in points)
				if (i == 0)
					p.moveTo(sx(q[0]), sy(q[1]));
				else
					p.lineTo(sx(q[0]), sy(q[1]));
			if (closed)
				p.close();
			return p;
		}
		// Whether any of `points`, `reach` pixels round, can be inside the map's box: what lies beyond it is clipped, so it is not made.
		function near(points:Array<Array<Float>>, reach:Float):Bool {
			var left = true, right = true, above = true, below = true;
			for (q in points) {
				var x = sx(q[0]), y = sy(q[1]);
				left = left && x < -reach;
				right = right && x > w + reach;
				above = above && y < -reach;
				below = below && y > h + reach;
			}
			return !(left || right || above || below);
		}
		function fill(layer:String, colour:Int, alpha = 1.0)
			for (shape in (Reflect.field(data.layers, layer) : Array<Array<Array<Float>>>))
				if (shape.length > 2 && near(shape, 1))
					ctx.fillPath(path(shape, true), Brush.solid(colour, alpha));
		function stroke(layer:String, width:Float, colour:Int, ?dash:Array<Float>)
			for (line in (Reflect.field(data.layers, layer) : Array<Array<Array<Float>>>))
				if (line.length > 1 && near(line, width))
					ctx.strokePath(path(line, false), new Stroke(width, Round, Round, 4, dash), Brush.solid(colour));

		ctx.pushClipRect(0, 0, w, h, 12);
		ctx.fillRect(0, 0, w, h, Brush.solid(style.land));
		fill("green", style.green);
		fill("water", style.water);
		stroke("canal", 7 * scale * 2, style.water);
		fill("building", style.building);
		stroke("rail", 1, style.rail, [3, 3]);
		stroke("service", 1.4, style.service);
		stroke("pedestrian", 1.2, style.service, [2, 2]);
		// Streets: each a casing a little wider than it, then the street, the main roads widest.
		stroke("minor", 4.2, style.casing);
		stroke("major", 6.4, style.casing);
		stroke("minor", 3, style.minor);
		stroke("major", 5, style.major);

		// The route: a soft glow, then the line, from the car to the first charger.
		// To the first charger the route is the street map's own; to another, a way round the corner from the car.
		var chargers:Array<Dynamic> = data.places.chargers;
		var route:Array<Array<Float>> = data.route;
		var start:Array<Float> = data.places.car;
		if (destination > 0 && destination < chargers.length) {
			var to:Array<Float> = chargers[destination].at;
			route = [start, [start[0], to[1]], to];
		}
		if (guiding) {
			ctx.strokePath(path(route, false), new Stroke(9, Round, Round), Brush.solid(accent, 0.22));
			ctx.strokePath(path(route, false), new Stroke(3.5, Round, Round), Brush.solid(accent));
			// Light running along the route toward the charger, `flow` pixels along its dashes.
			ctx.strokePath(path(route, false), new Stroke(1.6, Round, Round, 4, [4, 12], -flow), Brush.solid(0xffffff, 0.85));
		}

		for (i => c in chargers) {
			var x = sx(c.at[0]), y = sy(c.at[1]), colour = free[i];
			ctx.fillCircle(x, y + 1.5, 10, Brush.radial(x, y + 1.5, 10).stop(0, 0x000000, 0.25).stop(1, 0x000000, 0));
			ctx.fillCircle(x, y, 8.5, Brush.solid(0xffffff));
			ctx.fillCircle(x, y, 6.5, Brush.solid(colour));
			// A bolt.
			ctx.fillPath(new Path().moveTo(x + 0.8, y - 4.2).lineTo(x - 2.4, y + 0.6).lineTo(x - 0.1, y + 0.6).lineTo(x - 0.8, y + 4.2)
				.lineTo(x + 2.4, y - 0.6).lineTo(x + 0.1, y - 0.6).close(), Brush.solid(0xffffff));
		}

		var at:Array<Float> = data.places.car;
		var x = sx(at[0]), y = sy(at[1]);
		ctx.fillCircle(x, y, 18, Brush.radial(x, y, 18).stop(0, accent, 0.35).stop(1, accent, 0));
		if (car != null) {
			// Turned to face along the route, toward its first point some 30 m on: the picture's nose points up.
			var next = route[route.length - 1];
			for (q in route)
				if (Math.sqrt((q[0] - at[0]) * (q[0] - at[0]) + (q[1] - at[1]) * (q[1] - at[1])) > 30) {
					next = q;
					break;
				}
			var heading = Math.atan2(sy(next[1]) - y, sx(next[0]) - x) + Math.PI / 2;
			var length = 24.0, width = length * car.width / car.height;
			ctx.pushTransform(ashui.draw.Affine.translation(x, y).after(ashui.draw.Affine.rotation(heading)));
			ctx.fillRect(-width / 2 + 1, -length / 2 + 2, width, length, Brush.solid(0x000000, 0.18), width / 2);
			ctx.image(car, -width / 2, -length / 2, width, length);
			ctx.popTransform();
		} else {
			ctx.fillCircle(x, y, 7, Brush.solid(0xffffff));
			ctx.fillCircle(x, y, 5, Brush.solid(accent));
		}

		ctx.text("© OpenStreetMap", w - 6, h - 6, Brush.solid(style.label, 0.9), {size: 8, weight: 500, align: TextAlignment.End, baseline: TextBaseline.Bottom});
		ctx.popClip();
	}
}
