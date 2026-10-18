import ashui.canvaskit.Environment;
import ashui.canvaskit.Gltf;
import ashui.canvaskit.GltfPose;
import ashui.draw.DrawContext;
import ashui.draw3d.Material;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;

/**
	The banner's car: "Free Mazda 6 Sedan 2011 AR/VR, LowPoly 3D Model" by
	3D_Mill (CC-BY-4.0, `tools/snapshot/assets/3d/Mazda6/`). Its one texture
	paints the whole car, white, on a clean low-poly body; its metal and
	roughness map leaves the body and glass glossy and the trim matte. Here
	its paint is tinted, and it is stood on the floor with its nose down -z.
**/
class BannerCar {
	public static inline var PATH = "../assets/3d/Mazda6/scene.gltf";

	/** The wheels' node names, front first. **/
	static final WHEELS = ["FL", "FR", "RL", "RR"];

	final model:Gltf;
	final pose:GltfPose;
	final at:Mat4;
	final tint:Material->Material;
	final wheels:Array<Int>;
	final rest:Array<Quat>;

	/** Lengthwise in metres, from the model. **/
	public final length:Float;

	/** The car with its paint multiplied by `paint`, and `metallic` (the model's own map marks it all metal-capable, its roughness keeping trim and tyres matte), and with `toon` shaded in bands (`CarToon`). **/
	public function new(paint:Int, metallic = 0.0, toon = false) {
		// A page draws the scene at most a few thousand pixels wide, and decodes and uploads each texture in the time it has.
		model = Gltf.load(PATH, #if wasm {maxTextureSize: 2048} #else null #end);
		blankBadge(model.meshes[0].primitives[0].mesh);
		pose = new GltfPose(model);
		var size = model.max.sub(model.min), centre = model.min.add(model.max).scale(0.5);
		// Its length runs along x with its nose toward -x: a quarter turn clockwise, seen from above, puts the nose down -z.
		var turn = -Math.PI / 2;
		length = Math.max(size.x, size.z);
		at = Mat4.compose(new Vec3(0, -model.min.y, 0), Quat.axisAngle(Vec3.UP, turn), Vec3.ONE).mul(Mat4.translation(new Vec3(-centre.x, 0, -centre.z)));
		var tinted = new haxe.ds.ObjectMap<Material, Material>();
		tint = m -> {
			var t = tinted.get(m);
			if (t == null)
				tinted.set(m, t = m.with({baseColor: paint, metallic: metallic, shader: toon ? CarToon.WGSL : null}));
			t;
		};
		wheels = [for (name in WHEELS) [for (i in 0...model.nodes.length) if (model.nodes[i].name == name) i][0]];
		rest = [for (w in wheels) pose.rotations[w]];
	}

	/**
		Blanks the grille's badge, a small piece of the body standing proud of
		the grille: its points, within 7.6 cm of its middle and in front of the
		grille, all read the plain dark disc the texture now paints where the
		badge was, and take the grille's facing, so its relief no longer shades.
		The bumper below and the grille's frame above are kept out by their
		depth and by the part of the texture they read. It runs before the mesh
		is first drawn, which uploads it. Coordinates are the body mesh's own,
		in centimetres, its nose toward +z.
	**/
	static function blankBadge(mesh:ashui.draw3d.MeshData):Void {
		var v = mesh.vertices, stride = ashui.draw3d.MeshData.STRIDE;
		var no = ashui.draw3d.MeshData.NORMAL_OFFSET, uo = ashui.draw3d.MeshData.UV_OFFSET;
		var cy = -19.8;
		inline function at(i:Int, o:Int):Vec3
			return new Vec3(v.getFloat(i * stride + o), v.getFloat(i * stride + o + 4), v.getFloat(i * stride + o + 8));
		inline function reach(p:Vec3):Float
			return Math.sqrt(p.x * p.x + (p.y - cy) * (p.y - cy));
		// The bumper and the grille's frame read a strip low in the texture.
		inline function frame(i:Int):Bool
			return v.getFloat(i * stride + uo + 4) > 3600 / 4096 && v.getFloat(i * stride + uo) > 1200 / 4096 && v.getFloat(i * stride + uo) < 1520 / 4096;
		// The grille's facing, from the grille round the badge.
		var facing = Vec3.ZERO;
		for (i in 0...mesh.vertexCount) {
			var p = at(i, 0), r = reach(p);
			if (r > 9.5 && r < 14 && p.z > 225.5 && p.z < 230.5 && p.y > -27 && !frame(i))
				facing = facing.add(at(i, no));
		}
		if (facing.length() < 1e-9)
			return;
		facing = facing.normalize();
		for (i in 0...mesh.vertexCount) {
			var p = at(i, 0);
			if (reach(p) > 7.6 || p.z < 227.5 || p.z > 234 || frame(i))
				continue;
			for (k in 0...3)
				v.setFloat(i * stride + no + k * 4, k == 0 ? facing.x : k == 1 ? facing.y : facing.z);
			v.setFloat(i * stride + uo, 2670 / 4096);
			v.setFloat(i * stride + uo + 4, 965 / 4096);
		}
	}

	/** Turns the wheels to `angle` radians about their axles, as if rolling forward. **/
	public function roll(angle:Float):Void
		for (k in 0...wheels.length)
			pose.rotations[wheels[k]] = rest[k].mul(Quat.axisAngle(new Vec3(1, 0, 0), angle));

	/** Draws the car turned `turn` radians about its middle, anticlockwise seen from above. **/
	public function draw(ctx:DrawContext, turn = 0.0):Void
		pose.draw(ctx, turn == 0 ? at : Mat4.rotation(Quat.axisAngle(Vec3.UP, turn)).mul(at), tint);

	/**
		A product photographer's studio as light from every direction: a
		broad softbox overhead, a long strip light low on either side that
		lays a highlight along the car's flanks, and walls falling softly to
		the floor. `dark` gives a dark studio lit only by the softbox and the
		strips.
	**/
	public static function studio(dark:Bool):Environment
		return Environment.fromFunction(128, d -> {
			var wall = dark ? 0.18 : 0.6, floor = dark ? 0.05 : 0.2, top = dark ? 0.36 : 0.9;
			var base = floor + (wall - floor) * smoothstep(-0.95, 0.25, d.y);
			base += (top - base) * smoothstep(0.0, 1.0, d.y);
			var softbox = (dark ? 1.4 : 1.1) * smoothstep(0.45, 1.0, d.y);
			var strip = (dark ? 1.0 : 0.8) * Math.exp(-Math.pow((d.y - 0.16) / 0.1, 2)) * smoothstep(0.2, 0.95, Math.abs(d.x));
			var v = base + softbox + strip;
			new Vec3(v, v, v * (dark ? 1.04 : 1.0));
		});

	static inline function smoothstep(a:Float, b:Float, t:Float):Float {
		var c = (t - a) / (b - a);
		c = c < 0 ? 0 : c > 1 ? 1 : c;
		return c * c * (3 - 2 * c);
	}
}
