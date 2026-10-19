import ashui.draw3d.BcTexture;
import ashui.draw3d.BcImage;
import ashui.draw3d.TextureRole;
import ashui.types.Bitmap;
import haxe.io.Path;

/**
	Writes the block-compressed texture files a glTF model's images are read from by `Gltf.load`: for each image and each way
	the model's materials read it, `name.color.dds`, `.data.dds`, `.occlusion.dds` or `.normal.dds` beside the image, BC1 (BC3
	where colour has alpha), BC4 or BC5, every mip level. A program that loads the model then uploads them as they are and
	never decodes the image.

	    run.sh model.gltf [--max 2048] [--only color,data]

	`--max` shrinks an image whose side is longer first, keeping its shape and each side a multiple of 4 (the car in the
	dashboard is shown at about 700 pixels, so 2048 is plenty); an image whose sides are not multiples of 4 is left alone, as a
	block texture's must be. Images inside a `.glb`, or as data URIs, have no file to put one beside.
**/
class BcPack {
	static function main() {
		var args = Sys.args();
		var path:Null<String> = null, max = 2048, only:Null<Array<String>> = null;
		var i = 0;
		while (i < args.length) {
			switch args[i] {
				case "--max":
					max = Std.parseInt(args[++i]);
				case "--only":
					only = args[++i].split(",");
				case file:
					path = file;
			}
			i++;
		}
		if (path == null || StringTools.endsWith(path, ".glb")) {
			Sys.println("usage: bcpack model.gltf [--max 2048] [--only color,data,occlusion,normal]");
			Sys.exit(2);
		}
		var json:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
		var dir = Path.directory(path);
		var textures:Array<Dynamic> = json.textures != null ? json.textures : [];
		var images:Array<Dynamic> = json.images != null ? json.images : [];
		// Each image and the ways the materials read it, in order of first use.
		var wanted = new Map<String, {uri:String, role:TextureRole}>();
		var order:Array<String> = [];
		function want(info:Dynamic, role:TextureRole) {
			if (info == null || info.index == null)
				return;
			var t = textures[info.index];
			var image = t == null || t.source == null ? null : images[t.source];
			if (image == null || image.uri == null || StringTools.startsWith(image.uri, "data:"))
				return;
			var key = image.uri + "/" + role.word();
			if (!wanted.exists(key)) {
				wanted.set(key, {uri: image.uri, role: role});
				order.push(key);
			}
		}
		for (m in (json.materials != null ? (json.materials : Array<Dynamic>) : [])) {
			var pbr:Dynamic = m.pbrMetallicRoughness != null ? m.pbrMetallicRoughness : {};
			want(pbr.baseColorTexture, TextureRole.Color);
			want(pbr.metallicRoughnessTexture, TextureRole.Data);
			want(m.normalTexture, TextureRole.Normal);
			want(m.occlusionTexture, TextureRole.Occlusion);
			want(m.emissiveTexture, TextureRole.Color);
		}
		var written = 0, bytes = 0;
		for (key in order) {
			var w = wanted.get(key);
			if (only != null && only.indexOf(w.role.word()) < 0)
				continue;
			var name = StringTools.urlDecode(w.uri);
			var file = dir == "" ? name : Path.join([dir, name]);
			var bitmap = Bitmap.fromBytes(sys.io.File.getBytes(file));
			var from = '${bitmap.width}x${bitmap.height}';
			bitmap.shrink(max);
			if (bitmap.width % 4 != 0 || bitmap.height % 4 != 0) {
				Sys.println('skipped $name: ${bitmap.width}x${bitmap.height} is not a multiple of 4 on both sides');
				continue;
			}
			var made = BcTexture.of(bitmap, w.role);
			var dot = file.lastIndexOf(".");
			var out = (dot > file.lastIndexOf("/") ? file.substr(0, dot) : file) + "." + w.role.word() + ".dds";
			var data = made.toDds();
			sys.io.File.saveBytes(out, data);
			written++;
			bytes += data.length;
			Sys.println('wrote $out: $from as ${bitmap.width}x${bitmap.height}, ${made.levels.length} levels, ${Math.round(data.length / 1048576 * 10) / 10} MB');
		}
		Sys.println('$written files, ${Math.round(bytes / 1048576 * 10) / 10} MB');
	}
}
