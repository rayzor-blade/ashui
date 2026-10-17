import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.text.Fonts;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Text;

/** Fonts a program bundles are found by the family name they carry (git-bug 0c8c9a0). **/
class BundledFonts {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok)
			throw name + (detail == null ? "" : " " + Std.string(detail));
		checks++;
		Sys.println('ok   $name');
	}

	/** The width of `text` at 16 pixels in `family`, where a capital M of the bundled face is half an em. **/
	static function widthOf(text:String, family:String):Float {
		var tree = new LayoutTree();
		var label = new Text(text, {fontSize: 16}, tree);
		label.node.set(Prop.FontFamily, family);
		var root = new Div({flexDirection: Column, alignItems: Start}, [label], tree);
		tree.flush();
		tree.computeLayout(root.node, 400, 100);
		var width = tree.getBounds(label.node).width;
		tree.dispose();
		return width;
	}

	// The program runs in bin, the compiler in tests: embedded paths are relative to the compiler, loaded ones to the program.
	static function main() {
		var added = Fonts.embed("fixtures/text/regular.ttf");
		check("an embedded font adds its face", added >= 1, added);
		var width = widthOf("MMMM", "Blinc Embedded Fixture");
		check("text in its family is set in the bundled face: four capital Ms at 16px are 32px wide", Math.abs(width - 32) < 0.5, width);
		check("a WOFF2 font adds its face", Fonts.register(sys.io.File.getBytes("../fixtures/text/regular.woff2")) >= 1);
		check("a font file is loaded by path", Fonts.load("../fixtures/text/regular.ttf") >= 1);
		var threw = false;
		try
			Fonts.register(haxe.io.Bytes.ofString("not a font"))
		catch (e:Dynamic)
			threw = true;
		check("bytes that are no font throw", threw);
		Sys.println('ALL PASSED ($checks)');
	}
}
