import ashui.components.CodeEditor;
import ashui.core.render.Offscreen;
import ashui.layout.DisplayList;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Ref;
import gpu.GpuTextureViewDescriptor;

/**
	A code editor with few lines in a tall window has most of its row slots empty. A slot at no opacity with more than one painted
	node under it is drawn into a layer, which is a render pass over a texture of the window's size; a hidden one is not drawn, so
	the frame has no layers.
**/
class EditorLayersPixels {
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw what + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $what');
	}

	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree(), editor = new Ref<CodeEditor>(), dispose = () -> {};
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={600} height={700} class="flex flex-col"><code-editor ref={editor} language="haxe" value={"class A {\n\tvar x = 1;\n}\n"} lineNumbers={true} folding={true} gutterMarkers={true} class="flex-1 min-h-0"/></div>;
		});
		var off = Offscreen.create();
		off.clearAlpha = 1.0;
		off.clear = 0xffffff;
		var texture = off.createTexture(600, 700);
		var view = texture.createView(new GpuTextureViewDescriptor());
		for (i in 0...4)
			off.render(root, view, 600, 700);
		var list = @:privateAccess off.list;
		var layers = 0, text = 0;
		for (i in 0...list.count) {
			if (list.kind(i) == DisplayList.PRIM_LAYER_BEGIN)
				layers++;
			if (list.kind(i) == DisplayList.PRIM_TEXT)
				text++;
		}
		check("the editor's text is drawn", text > 10, text);
		check("its empty row slots and fold buttons make no layers", layers == 0, layers);
		dispose();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
