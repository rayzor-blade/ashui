import ashui.layout.LayoutTree;
import ashui.svg.Icon;
import ashui.svg.SvgDocument;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Svg;

@:build(ashui.svg.IconSet.build(["icons-a", "icons-b"]))
private class Icons {}

@:build(ashui.svg.IconSet.build("icons-b"))
private class OnlyB {}

/** An IconSet class has a typed, lazily made constant per SVG file, from every directory it is given (git-bug abb6355). **/
class IconSets {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : " " + Std.string(detail));
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		check("no document is made before an icon is read", @:privateAccess SvgDocument.nextId == 0, @:privateAccess SvgDocument.nextId);
		var play:SvgDocument = Icons.PLAY;
		check("only the icon read is made", @:privateAccess SvgDocument.nextId == 1, @:privateAccess SvgDocument.nextId);
		check("an icon keeps its size and its currentColor mask", play.width == 24 && play.height == 24 && play.mask);
		check("reading again gives the same document", Icons.PLAY == play);
		check("a file in a folder is a constant, the folder not in its name", Icons.PAUSE.width == 24);
		check("hyphens become underscores", Icons.SAVE_3_LINE.width == 32 && Icons.SAVE_3_LINE.height == 16);
		check("a name starting with a digit takes an underscore", Icons._4K.mask);
		check("an icon with fixed paints is not a mask", !Icons.SAVE_3_LINE.mask);
		check("a second directory's icons are in the same class", Icons.SAVE_3_LINE == OnlyB.SAVE_3_LINE);
		var asIcon:Icon = Icons.PLAY;
		check("a constant is an icon prop", (asIcon : SvgDocument) == play);
		check("the tint is supplied without changing the geometry", play.withColor("#ff0000").indexOf('color="#ff0000"') >= 0 && play.markup.indexOf("currentColor") >= 0);
		var tree = new LayoutTree();
		var icon = new Svg(Icons.PLAY, {width: 20, height: 20}, tree);
		var holder = new Div({flexDirection: Column, alignItems: Start}, [icon], tree);
		tree.flush();
		tree.computeLayout(holder.node, 100, 100);
		var drawn = tree.getBounds(icon.node);
		check("an icon is drawn at the size it is given", drawn != null && Math.abs(drawn.width - 20) < 0.5 && Math.abs(drawn.height - 20) < 0.5, drawn);
		tree.dispose();
		Sys.println('ALL PASSED ($checks)');
	}
}
