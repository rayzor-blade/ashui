import ashui.core.render.Offscreen;
import ashui.layout.LayoutTree;
import ashui.layout.Element;
import ashui.reactive.Owner;
import ashui.types.Bitmap;
import ashui.types.Brush;
import ashui.ui.Div;
import ashui.ui.Image;
import ashui.input.Scroll;
import gpu.GpuTextureViewDescriptor;

/** Exercises opt-in pixel residency without a document renderer or extension VM. **/
class ImageResidencyPixels {
	static function check(what:String, value:Bool) {
		if (!value) throw what;
		Sys.println('ok   $what');
	}

	static function main() {
		var source = haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAMAAAADCAYAAABWKLW/AAAAIElEQVR4nGNkOGH0n/kNw08QZuJi0GCAYRYQwczAAMYAx18Gn/YiqQYAAAAASUVORK5CYII=");
		var gpu = Offscreen.create();
		var texture = gpu.createTexture(400, 200), view = texture.createView(new GpuTextureViewDescriptor());
		for (optIn in [false, true]) {
			var tree = new LayoutTree(), stop:Void->Void = null, bitmap:Bitmap = null, viewport:Div = null;
			var root = Owner.root(tree, cleanup -> {
				stop = cleanup;
				viewport = new Div({width:400, height:200, virtualizeImages:optIn, overflow:ashui.types.Style.Overflow.Scroll,
					flexDirection:ashui.types.Style.FlexDirection.Column});
				bitmap = Bitmap.fromBytes(source);
				Owner.onCleanup(bitmap.dispose);
				viewport.appendChild(new Image(bitmap, {width:400, height:200}));
				viewport.appendChild(new Div({height:2000, flexShrink:0}));
				return viewport;
			});
			function draw() { tree.flush(); tree.computeLayout(root.node, 400, 200); gpu.renderTree(tree, root.node, view, 400, 200); }
			draw(); Scroll.at(viewport.node.id, tree).visibility = "hidden"; draw();
			var pixels = gpu.readRgba8(texture, 400, 200);
			var original = pixels.sub(0, pixels.length);
			check('visible bitmap is decoded ($optIn)', bitmap.decoded());
			Scroll.at(viewport.node.id, tree).jumpTo(0, 1000); draw();
			check('only opted-in scroll releases offscreen pixels ($optIn)', bitmap.decoded() != optIn);
			var atlas = @:privateAccess gpu.renderer.imageAtlas;
			if (optIn) {
				check('offscreen entries are removed', !(@:privateAccess atlas.entries).iterator().hasNext());
				check('offscreen texture shrinks', (@:privateAccess atlas.size) == 256);
			}
			for (_ in 0...3) {
				Scroll.at(viewport.node.id, tree).jumpTo(0, 0); draw();
				check('returning bitmap is decoded ($optIn)', bitmap.decoded());
				check('returning image pixels are unchanged ($optIn)', gpu.readRgba8(texture, 400, 200).compare(original) == 0);
				Scroll.at(viewport.node.id, tree).jumpTo(0, 1000); draw();
				check('repeated scroll releases opted-in pixels ($optIn)', bitmap.decoded() != optIn);
			}
			ashui.ui.ImageResidency.configure(viewport.node, false); draw();
			check('disabling opt-in restores pixels', bitmap.decoded());
			stop(); tree.dispose();
			check('owner disposal frees pixels', !bitmap.decoded());
		}
		// An unmanaged Image, a raw slot and a background brush protect a shared source.
		for (mode in ["image", "brush", "slot", "canvas", "managed", "nested-opt-out"]) {
			var tree = new LayoutTree(), stop:Void->Void = null, bitmap:Bitmap = null, viewport:Div = null;
			var root = Owner.root(tree, cleanup -> {
				stop = cleanup;
				var outer = new Div({width:400, height:200, flexDirection:ashui.types.Style.FlexDirection.Row});
				viewport = new Div({width:200, height:200, virtualizeImages:true, overflow:ashui.types.Style.Overflow.Scroll,
					flexDirection:ashui.types.Style.FlexDirection.Column});
				bitmap = Bitmap.fromBytes(source); Owner.onCleanup(bitmap.dispose);
				var image = new Image(bitmap, {width:200, height:200});
				if (mode == "nested-opt-out") viewport.appendChild(new Div({virtualizeImages:false}, [image]));
				else viewport.appendChild(image);
				viewport.appendChild(new Div({height:2000, flexShrink:0})); outer.appendChild(viewport);
				switch mode {
					case "image": outer.appendChild(new Image(bitmap, {width:200, height:200}));
					case "brush": outer.appendChild(new Div({width:200, height:200, bg:Brush.bitmap(bitmap)}));
					case "canvas":
						var canvas = new ashui.ui.Canvas({draw:ctx -> ctx.image(bitmap, 0, 0, 200, 200)});
						canvas.node.set(ashui.layout.Prop.Width, (200:Single)); canvas.node.set(ashui.layout.Prop.Height, (200:Single));
						outer.appendChild(canvas);
					case "managed":
						outer.appendChild(new Div({id:"second", width:200, height:200, virtualizeImages:true, overflow:ashui.types.Style.Overflow.Scroll,
							flexDirection:ashui.types.Style.FlexDirection.Column}, [new Image(bitmap, {width:200, height:200}), new Div({height:2000, flexShrink:0})]));
					case "nested-opt-out":
					case _: var escaped = bitmap.slot;
				}
				return outer;
			});
			tree.flush(); tree.computeLayout(root.node, 400, 200); gpu.renderTree(tree, root.node, view, 400, 200);
			var before = gpu.readRgba8(texture,400,200);
			Scroll.at(viewport.node.id, tree).jumpTo(0, 1000);
			tree.flush(); tree.computeLayout(root.node, 400, 200); gpu.renderTree(tree, root.node, view, 400, 200);
			check('shared $mode keeps bitmap resident', bitmap.decoded());
			if (["image", "brush", "canvas", "managed"].indexOf(mode) >= 0) {
				var after = gpu.readRgba8(texture,400,200), same = true;
				for (y in 0...200) for (x in 200...400) for (channel in 0...4) {
					var offset = (y*400+x)*4+channel;
					if (before.get(offset) != after.get(offset)) same = false;
				}
				check('atlas repack preserves shared $mode pixels', same);
			}
			if (mode == "managed") {
				var second = ashui.css.Css.query(tree, root.node.id, "#second")[0];
				Scroll.at(second, tree).jumpTo(0,1000);
				tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
				check('all managed shared uses offscreen release pixels', !bitmap.decoded());
			}
			stop(); tree.dispose();
		}
		var tree = new LayoutTree(), stop:Void->Void = null, viewport:Div = null;
		var doc = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 400 200"><rect width="400" height="200" fill="#ff0000"/></svg>');
		var root = Owner.root(tree, cleanup -> {
			stop=cleanup;
			viewport = new Div({width:400,height:200,virtualizeImages:true,overflow:ashui.types.Style.Overflow.Scroll,
				flexDirection:ashui.types.Style.FlexDirection.Column}, [new ashui.ui.Svg(doc),new Div({height:2000,flexShrink:0})]);
			return viewport;
		});
		tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
		var before=gpu.readRgba8(texture,400,200);
		Scroll.at(viewport.node.id,tree).visibility="hidden";
		Scroll.at(viewport.node.id,tree).jumpTo(0,1000);
		tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
		var atlas = @:privateAccess gpu.renderer.imageAtlas;
		check('SVG-only scrolling evicts atlas entries', !(@:privateAccess atlas.entries).iterator().hasNext() && (@:privateAccess atlas.size)==256);
		Scroll.at(viewport.node.id,tree).jumpTo(0,0);
		tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
		check('SVG reentry keeps its pixels', gpu.readRgba8(texture,400,200).compare(before)==0);
		stop(); tree.dispose();
		check('image uses leave the residency registry', (@:privateAccess ashui.ui.ImageResidency.uses.length) == 0);
		// Explicit resource disposal also reclaims caches outside virtualized scroll containers.
		for (vector in [false, true]) {
			var tree = new LayoutTree(), stop:Void->Void = null, bitmap:Bitmap = null, doc:ashui.svg.SvgDocument = null;
			var kept = Bitmap.fromBytes(source);
			var root = Owner.root(tree, cleanup -> {
				stop = cleanup;
				var image:Element;
				if (vector) {
					doc = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 2048 2048"><rect width="2048" height="2048" fill="#ff0000"/></svg>');
					image = new ashui.ui.Svg(doc, {width:2048, height:2048});
				} else {
					bitmap = Bitmap.fromBytes(source);
					image = new Image(bitmap, {width:2048, height:2048});
				}
				return new Div({width:400,height:200,overflow:ashui.types.Style.Overflow.Hidden}, [image]);
			});
			tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
			var atlas = @:privateAccess gpu.renderer.imageAtlas;
			check('a 2048-pixel image needs a 2048-pixel atlas ($vector)', (@:privateAccess atlas.size)==2048);
			stop(); tree.dispose();
			if (vector) {
				var revision = ashui.svg.SvgDocument.disposalRevision;
				doc.dispose(); doc.dispose();
				check('SVG disposal is idempotent', ashui.svg.SvgDocument.get(doc.id)==null && ashui.svg.SvgDocument.disposalRevision==revision+1);
				check('disposed SVG content can be parsed again', ashui.svg.SvgDocument.parse(doc.markup).id!=doc.id);
			} else bitmap.dispose();
			tree = new LayoutTree();
			root = Owner.root(tree, cleanup -> {stop=cleanup; return new Div({width:400,height:200}, [new Image(kept,{width:32,height:32})]);});
			tree.flush(); tree.computeLayout(root.node,400,200); gpu.renderTree(tree,root.node,view,400,200);
			check('disposal shrinks the atlas while another image remains ($vector)', (@:privateAccess atlas.size)==256);
			var pixels = gpu.readRgba8(texture,400,200);
			check('remaining image is still drawn after repack ($vector)', pixels.get((16*400+16)*4+3)>0);
			stop(); tree.dispose(); kept.dispose();
		}
		view.destroy(); texture.destroy();
	}
}
