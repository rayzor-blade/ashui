import ashui.icons.Remix;
import ashui.svg.SvgDocument;

@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "own"]))
private class Combined {}

/** The Remix catalogue is typed constants that tint, and combines with an app's own icons (git-bug abb6355). **/
class RemixCatalogue {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : " " + Std.string(detail));
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		var play:SvgDocument = Remix.PLAY_LINE;
		check("a Remix icon is 24 by 24 and takes the text colour", play.width == 24 && play.height == 24 && play.mask);
		check("a name starting with a digit has an underscore", Remix._4K_LINE.width == 24 && Remix._24_HOURS_FILL.mask);
		check("fill and line forms are different icons", Remix.PLAY_FILL != Remix.PLAY_LINE);
		check("an icon is the same document each time it is read", Remix.SAVE_3_LINE == Remix.SAVE_3_LINE);
		check("a catalogue and an app's own icons make one class", Combined.PLAY_LINE == play && Combined._3D_MOVE.width == 24);
		check("an own icon with fixed strokes still takes the text colour", Combined._3D_MOVE.markup.indexOf("currentColor") >= 0);
		Sys.println('ALL PASSED ($checks)');
	}
}
