package ashui.canvaskit;

import ashui.canvaskit.GltfAnimation;
import ashui.draw.DrawContext;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import haxe.io.Bytes;

/**
	Where a glTF scene's nodes are, and its meshes' morph weights: at rest
	until an animation moves them. The time is the caller's; a game keeps
	its own clock, loops, blends or scrubs, and plays each frame:

	```haxe
	var pose = new GltfPose(drone);
	var clip = drone.animations[0];
	<scene-kit draw={ctx -> {
		pose.play(clip, time.get() % clip.duration);
		pose.draw(ctx);
	}} />;
	```

	`update` works out each node's transform in the scene into `matrices`,
	and `palette` a skin's joint matrices into a buffer ready to upload;
	`weights` holds each node's morph weights. A pass that skins or morphs
	the meshes itself reads them; `world` and `joints` give the same as
	`Mat4`s.
**/
class GltfPose {
	public final scene:Gltf;
	public final translations:Array<Vec3>;
	public final rotations:Array<Quat>;
	public final scales:Array<Vec3>;

	/** Each node's mesh's morph target weights. **/
	public final weights:Array<Array<Float>>;

	/** Bytes to a matrix in `matrices` and `palette`: sixteen 32-bit floats, column by column. **/
	public static inline var MATRIX_BYTES = 64;

	/** Each node's transform in the scene once `update` has run, `MATRIX_BYTES` a node in `Gltf.nodes` order. **/
	public final matrices:Bytes;

	/** The default scene's tree, each node after its parent. **/
	final order:Array<Int> = [];

	/** Each node's parent in that tree, -1 for a root or a node outside it. **/
	final above:Array<Int>;

	final reached:Array<Bool>;

	/** Each skin's inverse bind matrices as 32-bit floats, made the first time it is asked for. **/
	final binds:Array<Null<Bytes>>;

	final sampled:Array<Float> = [0, 0, 0, 0];
	final scratch = Bytes.alloc(MATRIX_BYTES);

	public function new(scene:Gltf) {
		this.scene = scene;
		translations = [for (n in scene.nodes) n.translation];
		rotations = [for (n in scene.nodes) n.rotation];
		scales = [for (n in scene.nodes) n.scale];
		weights = [for (n in scene.nodes) n.weights.copy()];
		matrices = Bytes.alloc(scene.nodes.length * MATRIX_BYTES);
		above = [for (_ in scene.nodes) -1];
		reached = [for (_ in scene.nodes) false];
		binds = [for (_ in scene.skins) null];
		function visit(i:Int, parent:Int, depth:Int) {
			if (depth > 64 || i < 0 || i >= reached.length || reached[i])
				return;
			reached[i] = true;
			above[i] = parent;
			order.push(i);
			for (c in scene.nodes[i].children)
				visit(c, i, depth + 1);
		}
		for (r in scene.roots)
			visit(r, -1, 0);
	}

	/** Every node back where the file has it. **/
	public function reset():Void {
		for (i in 0...scene.nodes.length) {
			var n = scene.nodes[i];
			translations[i] = n.translation;
			rotations[i] = n.rotation;
			scales[i] = n.scale;
			for (k in 0...n.weights.length)
				weights[i][k] = n.weights[k];
		}
	}

	/** The nodes `animation` moves where it has them at `time` seconds; the rest stay where they are. **/
	public function play(animation:GltfAnimation, time:Float):Void {
		for (c in animation.channels) {
			if (c.node < 0 || c.node >= scene.nodes.length)
				continue;
			switch c.path {
				case Translation:
					c.sampler.sample(time, sampled);
					translations[c.node] = new Vec3(sampled[0], sampled[1], sampled[2]);
				case Rotation:
					c.sampler.sample(time, sampled, true);
					rotations[c.node] = new Quat(sampled[0], sampled[1], sampled[2], sampled[3]);
				case Scale:
					c.sampler.sample(time, sampled);
					scales[c.node] = new Vec3(sampled[0], sampled[1], sampled[2]);
				case Weights:
					var into = weights[c.node];
					while (into.length < c.sampler.width)
						into.push(0);
					c.sampler.sample(time, into);
			}
		}
	}

	/** A node's transform in its parent. A node the file gives as a matrix keeps it. **/
	public function local(node:Int):Mat4 {
		var n = scene.nodes[node];
		return n.matrix != null ? n.matrix : Mat4.compose(translations[node], rotations[node], scales[node]);
	}

	/**
		Works out each node's transform in the scene into `matrices`, a
		parent's before its children's; a node outside the default scene's
		tree gets its own. With `-D ash_simd` each matrix product is four
		columns of four lanes.
	**/
	public function update():Void {
		for (i in 0...scene.nodes.length)
			if (!reached[i])
				writeLocal(i, matrices, i * MATRIX_BYTES);
		for (i in order)
			if (above[i] < 0)
				writeLocal(i, matrices, i * MATRIX_BYTES);
			else {
				writeLocal(i, scratch, 0);
				multiply(matrices, above[i] * MATRIX_BYTES, scratch, 0, matrices, i * MATRIX_BYTES, SIMD);
			}
	}

	/**
		A skin's joint matrices into `out` from `offset`, `MATRIX_BYTES` a
		joint in its `joints` order, as a joint buffer is uploaded: each
		joint's transform in the scene, as `update` last worked it out, times
		its inverse bind matrix. That takes a vertex from where the mesh has
		it at rest to where the joints put it in the scene; glTF has the
		skinned mesh's own node not place it, so it is drawn with no further
		transform.
	**/
	public function palette(skin:Int, out:Bytes, offset = 0):Void {
		var s = scene.skins[skin];
		var b = binds[skin];
		if (b == null) {
			b = Bytes.alloc(s.joints.length * MATRIX_BYTES);
			for (j in 0...s.joints.length)
				writeMat4(s.inverseBindMatrices[j], b, j * MATRIX_BYTES);
			binds[skin] = b;
		}
		for (j in 0...s.joints.length)
			multiply(matrices, s.joints[j] * MATRIX_BYTES, b, j * MATRIX_BYTES, out, offset + j * MATRIX_BYTES, SIMD);
	}

	/** Each node's transform in the scene, in `Gltf.nodes` order. **/
	public function world():Array<Mat4> {
		update();
		return [for (i in 0...scene.nodes.length) readMat4(matrices, i * MATRIX_BYTES)];
	}

	/** A skin's joint matrices as `palette` gives them, one a joint. **/
	public function joints(skin:Int):Array<Mat4> {
		update();
		var n = scene.skins[skin].joints.length;
		var out = Bytes.alloc(n * MATRIX_BYTES);
		palette(skin, out);
		return [for (j in 0...n) readMat4(out, j * MATRIX_BYTES)];
	}

	/**
		Draws the meshes of nodes without a skin where this pose puts them,
		all placed by `transform` too when it is given; morph targets are not
		applied. A skinned mesh is the game's to draw.
	**/
	public function draw(ctx:DrawContext, ?transform:Mat4):Void {
		update();
		for (i in 0...scene.nodes.length) {
			var n = scene.nodes[i];
			if (n.mesh < 0 || n.skin >= 0 || !reached[i])
				continue;
			var w = readMat4(matrices, i * MATRIX_BYTES);
			var m = transform != null ? transform.mul(w) : w;
			for (p in scene.meshes[n.mesh].primitives)
				ctx.drawMesh(p.mesh, m);
		}
	}

	/** Node `i`'s transform in its parent into `out` at `o`, as 32-bit floats column by column. **/
	function writeLocal(i:Int, out:Bytes, o:Int):Void {
		var m = scene.nodes[i].matrix;
		if (m != null) {
			writeMat4(m, out, o);
			return;
		}
		var t = translations[i], q = rotations[i], s = scales[i];
		var x = q.x, y = q.y, z = q.z, w = q.w;
		inline function put(k:Int, v:Float)
			out.setFloat(o + k * 4, v);
		put(0, (1 - 2 * (y * y + z * z)) * s.x);
		put(1, 2 * (x * y + w * z) * s.x);
		put(2, 2 * (x * z - w * y) * s.x);
		put(3, 0);
		put(4, 2 * (x * y - w * z) * s.y);
		put(5, (1 - 2 * (x * x + z * z)) * s.y);
		put(6, 2 * (y * z + w * x) * s.y);
		put(7, 0);
		put(8, 2 * (x * z + w * y) * s.z);
		put(9, 2 * (y * z - w * x) * s.z);
		put(10, (1 - 2 * (x * x + y * y)) * s.z);
		put(11, 0);
		put(12, t.x);
		put(13, t.y);
		put(14, t.z);
		put(15, 1);
	}

	static function writeMat4(m:Mat4, out:Bytes, o:Int):Void
		for (c in 0...4)
			for (r in 0...4)
				out.setFloat(o + (c * 4 + r) * 4, m.get(c, r));

	static function readMat4(b:Bytes, o:Int):Mat4
		return Mat4.ofColumns([for (k in 0...16) b.getFloat(o + k * 4)]);

	/** Whether matrix products go through ash-simd. **/
	static inline var SIMD = #if (ash_simd && hl) true #else false #end;

	/** `a` times `b` into `out`, each a column-major matrix of 32-bit floats at its offset; `out` is neither. **/
	static function multiply(a:Bytes, ai:Int, b:Bytes, bi:Int, out:Bytes, oi:Int, simd:Bool):Void {
		#if (ash_simd && hl)
		if (simd) {
			var pa:hl.Bytes = a, pb:hl.Bytes = b, po:hl.Bytes = out;
			var c0 = ash.simd.Float32x4.load(pa, ai), c1 = ash.simd.Float32x4.load(pa, ai + 16);
			var c2 = ash.simd.Float32x4.load(pa, ai + 32), c3 = ash.simd.Float32x4.load(pa, ai + 48);
			// Each column of the product: `a`'s columns weighted by that column of `b`.
			for (j in 0...4) {
				var o = bi + j * 16;
				var col = c0 * ash.simd.Float32x4.splat(pb.getF32(o)) + c1 * ash.simd.Float32x4.splat(pb.getF32(o + 4))
					+ c2 * ash.simd.Float32x4.splat(pb.getF32(o + 8)) + c3 * ash.simd.Float32x4.splat(pb.getF32(o + 12));
				col.store(po, oi + j * 16);
			}
			return;
		}
		#end
		for (j in 0...4)
			for (r in 0...4) {
				var v = 0.0;
				for (k in 0...4)
					v += a.getFloat(ai + (k * 4 + r) * 4) * b.getFloat(bi + (j * 4 + k) * 4);
				out.setFloat(oi + (j * 4 + r) * 4, v);
			}
	}
}
