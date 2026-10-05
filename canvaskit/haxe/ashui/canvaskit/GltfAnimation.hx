package ashui.canvaskit;

import haxe.io.Float32Array;

/** What of a node a channel moves. **/
enum GltfPath {
	Translation;
	Rotation;
	Scale;

	/** Its mesh's morph target weights. **/
	Weights;
}

/** How a sampler goes from one keyframe to the next. **/
enum GltfInterpolation {
	/** Each keyframe's value until the next. **/
	Step;

	/** Straight between keyframes; rotations along the shorter arc. **/
	Linear;

	/** A Hermite curve through the keyframes, each with the tangents in and out of it. **/
	CubicSpline;
}

/**
	A glTF animation: channels, each moving one thing of one node by a
	sampler's keyframes, over `duration` seconds.

	```haxe
	var pose = new GltfPose(drone);
	pose.play(drone.animations[0], time % drone.animations[0].duration);
	pose.draw(ctx);
	```
**/
class GltfAnimation {
	public final name:Null<String>;
	public final channels:Array<GltfChannel>;

	/** Its last keyframe's time, in seconds. **/
	public final duration:Float;

	public function new(name:Null<String>, channels:Array<GltfChannel>) {
		this.name = name;
		this.channels = channels;
		var end = 0.0;
		for (c in channels)
			if (c.sampler.times.length > 0)
				end = Math.max(end, c.sampler.times[c.sampler.times.length - 1]);
		duration = end;
	}
}

/** One thing of one node an animation moves. **/
class GltfChannel {
	/** The node's index in `Gltf.nodes`. **/
	public final node:Int;

	public final path:GltfPath;
	public final sampler:GltfSampler;

	public function new(node:Int, path:GltfPath, sampler:GltfSampler) {
		this.node = node;
		this.path = path;
		this.sampler = sampler;
	}
}

/**
	Keyframes: their times in seconds, ascending, and `width` numbers of
	value each (3 a translation or scale, 4 a rotation, as many as the
	mesh's morph targets for weights). A cubic spline's keyframe holds
	three of those, the tangent in, the value and the tangent out.
**/
class GltfSampler {
	public final times:Float32Array;
	public final values:Float32Array;
	public final interpolation:GltfInterpolation;
	public final width:Int;

	public function new(times:Float32Array, values:Float32Array, interpolation:GltfInterpolation, width:Int) {
		this.times = times;
		this.values = values;
		this.interpolation = interpolation;
		this.width = width;
	}

	/**
		The value at `time` seconds, `width` numbers into `out`; before the
		first keyframe its value, after the last the last's. `rotation` reads
		the values as quaternions: turned the shorter way, and of unit length.
		With `-D ash_simd` four numbers are blended at once.
	**/
	public function sample(time:Float, out:Array<Float>, rotation = false):Void
		blend(time, out, rotation, #if (ash_simd && hl) true #else false #end);

	function blend(time:Float, out:Array<Float>, rotation:Bool, simd:Bool):Void {
		var n = times.length;
		if (n == 0)
			return;
		// The keyframe at or before `time`, found by halving.
		var k = 0;
		if (time >= times[n - 1])
			k = n - 1;
		else if (time > times[0]) {
			var lo = 0, hi = n - 1;
			while (hi - lo > 1) {
				var mid = (lo + hi) >> 1;
				if (times[mid] <= time)
					lo = mid;
				else
					hi = mid;
			}
			k = lo;
		}
		var w = width;
		if (k == n - 1 || time <= times[0] || interpolation == Step) {
			var at = interpolation == CubicSpline ? k * 3 * w + w : k * w;
			for (c in 0...w)
				out[c] = values[at + c];
			return;
		}
		var t0 = times[k], dt = times[k + 1] - t0;
		var t = dt > 0 ? (time - t0) / dt : 0.0;
		// Every interpolation is a sum of keyframe values times weights: up to four values, at `at0`... with weights `w0`...
		var at0 = 0, at1 = 0, at2 = -1, at3 = -1;
		var w0 = 0.0, w1 = 0.0, w2 = 0.0, w3 = 0.0;
		switch interpolation {
			case CubicSpline:
				var t2 = t * t, t3 = t2 * t;
				var from = k * 3 * w, to = (k + 1) * 3 * w;
				at0 = from + w;
				w0 = 2 * t3 - 3 * t2 + 1;
				at1 = to + w;
				w1 = -2 * t3 + 3 * t2;
				at2 = from + 2 * w;
				w2 = (t3 - 2 * t2 + t) * dt;
				at3 = to;
				w3 = (t3 - t2) * dt;
			case _ if (rotation):
				var p = k * 4, q = p + 4;
				var dot = values[p] * values[q] + values[p + 1] * values[q + 1] + values[p + 2] * values[q + 2] + values[p + 3] * values[q + 3];
				var sign = dot < 0 ? -1.0 : 1.0;
				dot *= sign;
				at0 = p;
				at1 = q;
				w0 = 1 - t;
				w1 = t * sign;
				if (dot < 0.9995) {
					var theta = Math.acos(dot), s = Math.sin(theta);
					w0 = Math.sin((1 - t) * theta) / s;
					w1 = Math.sin(t * theta) / s * sign;
				}
			case _:
				at0 = k * w;
				at1 = at0 + w;
				w0 = 1 - t;
				w1 = t;
		}
		var c = 0;
		#if (ash_simd && hl)
		if (simd) {
			var data:hl.Bytes = values.view.buffer;
			var base = values.view.byteOffset;
			var last = Std.int(Math.max(Math.max(at0, at1), Math.max(at2, at3)));
			var v0 = ash.simd.Float32x4.splat(w0), v1 = ash.simd.Float32x4.splat(w1);
			var v2 = ash.simd.Float32x4.splat(w2), v3 = ash.simd.Float32x4.splat(w3);
			// Four lanes at a time while every value's four lie inside the keyframes.
			while (c + 4 <= w || (c < w && last + c + 4 <= values.length)) {
				var sum = ash.simd.Float32x4.load(data, base + (at0 + c) * 4) * v0 + ash.simd.Float32x4.load(data, base + (at1 + c) * 4) * v1;
				if (at2 >= 0)
					sum = sum + ash.simd.Float32x4.load(data, base + (at2 + c) * 4) * v2 + ash.simd.Float32x4.load(data, base + (at3 + c) * 4) * v3;
				sum.store(lanes, 0);
				for (l in 0...Std.int(Math.min(4, w - c)))
					out[c + l] = lanes.getF32(l * 4);
				c += 4;
			}
		}
		#end
		while (c < w) {
			var v = values[at0 + c] * w0 + values[at1 + c] * w1;
			if (at2 >= 0)
				v += values[at2 + c] * w2 + values[at3 + c] * w3;
			out[c] = v;
			c++;
		}
		if (rotation)
			normalize(out);
	}

	#if (ash_simd && hl)
	static final lanes = new hl.Bytes(16);
	#end

	static function normalize(q:Array<Float>):Void {
		var l = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
		if (l > 0)
			for (c in 0...4)
				q[c] /= l;
	}
}
