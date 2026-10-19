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
	/** The layers' shapes, as typed arrays made once: a cast of the parsed layer to its type copies it, tens of megabytes for the buildings, at each use. **/
	final layers = new Map<String, Array<Array<Array<Float>>>>();
	final car:Null<ashui.types.Bitmap>;

	/** The map at `path`, and the car drawn from above, nose up, at `carIcon`. **/
	public function new(path:String, ?carIcon:String) {
		data = haxe.Json.parse(ashui.core.Assets.text(path));
		for (name in Reflect.fields(data.layers))
			layers.set(name, (Reflect.field(data.layers, name) : Array<Array<Array<Float>>>));
		// What was parsed is not kept beside what was made from it.
		Reflect.setField(data, "layers", null);
		car = carIcon == null ? null : ashui.types.Bitmap.load(carIcon);
	}

	/**
		Draws the map `w` by `h`, framed on the route, the chargers and the
		car with `margin` pixels round them, in the light or dark scheme, the
		route in `accent`. `free` gives each charger's colour; `flow`
		moves the light running along the route, in pixels. It is `base` and
		`route` in one context; a page whose route moves draws them in two
		canvases, so the streets, which do not, are not made again each frame.
	**/
	public function draw(ctx:DrawContext, w:Float, h:Float, margin:Float, light:Bool, accent:Int, free:Array<Int>, flow = 0.0, destination = 0, zoom = 1.0,
			guiding = true, detail = true):Void {
		base(ctx, w, h, margin, light, zoom, detail);
		route(ctx, w, h, margin, accent, free, flow, destination, zoom, guiding);
	}

	function layerOf(name:String):Array<Array<Array<Float>>> {
		var shapes = layers.get(name);
		return shapes == null ? [] : shapes;
	}

	/** Where the map is laid in a box `w` by `h`: the route, the chargers and the car inside `margin`, scaled by `zoom`. **/
	function framing(w:Float, h:Float, margin:Float, zoom:Float):Framing {
		var marked:Array<Array<Float>> = (data.route : Array<Array<Float>>).concat([for (c in (data.places.chargers : Array<Dynamic>)) (c.at : Array<Float>)])
			.concat([(data.places.car : Array<Float>)]);
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (q in marked) {
			x0 = Math.min(x0, q[0]);
			x1 = Math.max(x1, q[0]);
			y0 = Math.min(y0, q[1]);
			y1 = Math.max(y1, q[1]);
		}
		return new Framing(w, h, Math.min((w - margin * 2) / (x1 - x0), (h - margin * 2) / (y1 - y0)) * zoom, (x0 + x1) / 2, (y0 + y1) / 2);
	}

	/**
		The land under the route: parks, water, buildings and streets, and the credit. It depends on the size, the scheme and the
		zoom, and on nothing that moves. A map too small for the detail leaves out what it would not show, the buildings, the
		rails, the paths and the side streets, and its credit, which the page then says in text.
	**/
	public function base(ctx:DrawContext, w:Float, h:Float, margin:Float, light:Bool, zoom = 1.0, detail = true):Void {
		var style = light ? LIGHT : DARK, f = framing(w, h, margin, zoom), scale = f.scale;
		function fill(layer:String, colour:Int, alpha = 1.0)
			for (shape in layerOf(layer))
				if (shape.length > 2 && f.near(shape, 1))
					ctx.fillPath(f.path(shape, true), Brush.solid(colour, alpha));
		function stroke(layer:String, width:Float, colour:Int, ?dash:Array<Float>)
			for (line in layerOf(layer))
				if (line.length > 1 && f.near(line, width))
					ctx.strokePath(f.path(line, false), new Stroke(width, Round, Round, 4, dash), Brush.solid(colour));

		ctx.pushClipRect(0, 0, w, h, 12);
		ctx.fillRect(0, 0, w, h, Brush.solid(style.land));
		fill("green", style.green);
		fill("water", style.water);
		stroke("canal", 7 * scale * 2, style.water);
		if (detail) {
			fill("building", style.building);
			stroke("rail", 1, style.rail, [3, 3]);
			stroke("service", 1.4, style.service);
			stroke("pedestrian", 1.2, style.service, [2, 2]);
		}
		// Streets: each a casing a little wider than it, then the street, the main roads widest.
		if (detail)
			stroke("minor", 4.2, style.casing);
		stroke("major", 6.4, style.casing);
		if (detail)
			stroke("minor", 3, style.minor);
		stroke("major", 5, style.major);
		if (detail)
			ctx.text("© OpenStreetMap", w - 6, h - 6, Brush.solid(style.label, 0.9), {size: 8, weight: 500, align: TextAlignment.End, baseline: TextBaseline.Bottom});
		ctx.popClip();
	}

	/** The route from the car to the charger chosen: the street map's own to the first charger, to another a way round the corner. **/
	function way(destination:Int):Array<Array<Float>> {
		var chargers:Array<Dynamic> = data.places.chargers;
		var route:Array<Array<Float>> = data.route;
		if (destination > 0 && destination < chargers.length) {
			var start:Array<Float> = data.places.car;
			var to:Array<Float> = chargers[destination].at;
			route = [start, [start[0], to[1]], to];
		}
		return route;
	}

	/** What is on the land and moves or changes: the route with its light, the chargers and the car; `line`, `light` and `markers` in one context. **/
	public function route(ctx:DrawContext, w:Float, h:Float, margin:Float, accent:Int, free:Array<Int>, flow = 0.0, destination = 0, zoom = 1.0, guiding = true):Void {
		line(ctx, w, h, margin, accent, destination, zoom, guiding);
		light(ctx, w, h, margin, flow, destination, zoom, guiding);
		markers(ctx, w, h, margin, accent, free, destination, zoom);
	}

	/** The route: a soft glow, then the line, from the car to the charger. It changes with the charger chosen, the zoom and the scheme, and nothing else. **/
	public function line(ctx:DrawContext, w:Float, h:Float, margin:Float, accent:Int, destination = 0, zoom = 1.0, guiding = true):Void {
		if (!guiding)
			return;
		var f = framing(w, h, margin, zoom), route = way(destination);
		ctx.pushClipRect(0, 0, w, h, 12);
		ctx.strokePath(f.path(route, false), new Stroke(9, Round, Round), Brush.solid(accent, 0.22));
		ctx.strokePath(f.path(route, false), new Stroke(3.5, Round, Round), Brush.solid(accent));
		ctx.popClip();
	}

	/** The light's dashes: this long, one in each `PERIOD` along the route. **/
	static inline var DASH = 4.0;

	static inline var PERIOD = 16.0;

	/** How many headings a dash has: one path each, so a dash is a path the painter has seen and only moves. **/
	static inline var HEADINGS = 32;

	/** The dash drawn at each heading, from the origin, as a path of its own. **/
	static final DASHES:Array<Path> = [
		for (k in 0...HEADINGS) {
			var angle = k * Math.PI * 2 / HEADINGS;
			new Path().moveTo(0, 0).lineTo(DASH * Math.cos(angle), DASH * Math.sin(angle));
		}
	];

	/**
		Light running along the route toward the charger, `flow` pixels along its dashes: all of the route a page that moves draws
		each frame. Each dash is one of `HEADINGS` short strokes, the nearest to the way the route runs there, moved to its place,
		so a canvas drawn again each frame has the triangles it made for a dash moved to the next, not made again for the whole
		route, a path of dozens of dashes with round caps.
	**/
	public function light(ctx:DrawContext, w:Float, h:Float, margin:Float, flow:Float, destination = 0, zoom = 1.0, guiding = true):Void {
		if (!guiding)
			return;
		var f = framing(w, h, margin, zoom), route = way(destination);
		// The route's points in the canvas, the distance along it at each, and the heading of each segment.
		var xs = [for (q in route) f.sx(q[0])], ys = [for (q in route) f.sy(q[1])];
		var at = [0.0], heading:Array<Float> = [];
		for (i in 1...xs.length) {
			var dx = xs[i] - xs[i - 1], dy = ys[i] - ys[i - 1];
			at.push(at[i - 1] + Math.sqrt(dx * dx + dy * dy));
			heading.push(Math.atan2(dy, dx));
		}
		var total = at[at.length - 1];
		if (xs.length < 2 || total < DASH)
			return;
		ctx.pushClipRect(0, 0, w, h, 12);
		var stroke = new Stroke(1.6, Round, Round), brush = Brush.solid(0xffffff, 0.85);
		var start = ((flow % PERIOD) + PERIOD) % PERIOD, segment = 0;
		var s = start;
		while (s + DASH <= total) {
			while (segment < heading.length - 1 && at[segment + 1] < s)
				segment++;
			var t = (s - at[segment]) / Math.max(1e-9, at[segment + 1] - at[segment]);
			var x = xs[segment] + (xs[segment + 1] - xs[segment]) * t, y = ys[segment] + (ys[segment + 1] - ys[segment]) * t;
			// A dash that runs round a corner is drawn along the chord of its two ends; one on a segment, along it exactly.
			var end = segment;
			while (end < heading.length - 1 && at[end + 1] < s + DASH)
				end++;
			var turn = heading[segment];
			if (end != segment) {
				var u = (s + DASH - at[end]) / Math.max(1e-9, at[end + 1] - at[end]);
				turn = Math.atan2(ys[end] + (ys[end + 1] - ys[end]) * u - y, xs[end] + (xs[end + 1] - xs[end]) * u - x);
			}
			var step = Math.round(turn / (Math.PI * 2) * HEADINGS);
			ctx.pushTransform(ashui.draw.Affine.translation(x, y));
			ctx.strokePath(DASHES[((step % HEADINGS) + HEADINGS) % HEADINGS], stroke, brush);
			ctx.popTransform();
			s += PERIOD;
		}
		ctx.popClip();
	}

	/** The chargers, each in the colour of how many of its places are free, and the car. **/
	public function markers(ctx:DrawContext, w:Float, h:Float, margin:Float, accent:Int, free:Array<Int>, destination = 0, zoom = 1.0):Void {
		var f = framing(w, h, margin, zoom), route = way(destination);
		ctx.pushClipRect(0, 0, w, h, 12);
		var chargers:Array<Dynamic> = data.places.chargers;
		for (i => c in chargers) {
			var x = f.sx(c.at[0]), y = f.sy(c.at[1]), colour = free[i];
			ctx.fillCircle(x, y + 1.5, 10, Brush.radial(x, y + 1.5, 10).stop(0, 0x000000, 0.25).stop(1, 0x000000, 0));
			ctx.fillCircle(x, y, 8.5, Brush.solid(0xffffff));
			ctx.fillCircle(x, y, 6.5, Brush.solid(colour));
			// A bolt.
			ctx.fillPath(new Path().moveTo(x + 0.8, y - 4.2).lineTo(x - 2.4, y + 0.6).lineTo(x - 0.1, y + 0.6).lineTo(x - 0.8, y + 4.2)
				.lineTo(x + 2.4, y - 0.6).lineTo(x + 0.1, y - 0.6).close(), Brush.solid(0xffffff));
		}

		var at:Array<Float> = data.places.car;
		var x = f.sx(at[0]), y = f.sy(at[1]);
		ctx.fillCircle(x, y, 18, Brush.radial(x, y, 18).stop(0, accent, 0.35).stop(1, accent, 0));
		if (car != null) {
			// Turned to face along the route, toward its first point some 30 m on: the picture's nose points up.
			var next = route[route.length - 1];
			for (q in route)
				if (Math.sqrt((q[0] - at[0]) * (q[0] - at[0]) + (q[1] - at[1]) * (q[1] - at[1])) > 30) {
					next = q;
					break;
				}
			var heading = Math.atan2(f.sy(next[1]) - y, f.sx(next[0]) - x) + Math.PI / 2;
			var length = 24.0, width = length * car.width / car.height;
			ctx.pushTransform(ashui.draw.Affine.translation(x, y).after(ashui.draw.Affine.rotation(heading)));
			ctx.fillRect(-width / 2 + 1, -length / 2 + 2, width, length, Brush.solid(0x000000, 0.18), width / 2);
			ctx.image(car, -width / 2, -length / 2, width, length);
			ctx.popTransform();
		} else {
			ctx.fillCircle(x, y, 7, Brush.solid(0xffffff));
			ctx.fillCircle(x, y, 5, Brush.solid(accent));
		}
		ctx.popClip();
	}
}

/** How the map sits in its box: a metre's pixels, and the map point at the middle. **/
private class Framing {
	public final w:Float;
	public final h:Float;
	public final scale:Float;
	final cx:Float;
	final cy:Float;

	public function new(w:Float, h:Float, scale:Float, cx:Float, cy:Float) {
		this.w = w;
		this.h = h;
		this.scale = scale;
		this.cx = cx;
		this.cy = cy;
	}

	public inline function sx(x:Float):Float
		return (x - cx) * scale + w / 2;

	public inline function sy(y:Float):Float
		return (y - cy) * scale + h / 2;

	public function path(points:Array<Array<Float>>, closed:Bool):Path {
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

	/** Whether any of `points`, `reach` pixels round, can be inside the map's box: what lies beyond it is clipped, so it is not made. **/
	public function near(points:Array<Array<Float>>, reach:Float):Bool {
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
}
