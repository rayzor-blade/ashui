import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;

/**
	Box shadows with no blur, beside blurred ones: a spread ring, an offset
	copy, a negative spread under an offset, each on square, rounded and
	squircle boxes; and inset ones, spread and offset, alone and with an
	outer layer.
**/
class ShadowEdges {
	static final CSS = '
		.page { flex-direction: column; gap: 36px; padding: 32px; width: 640px; height: 470px; background: #f8fafc; }
		.row { flex-direction: row; gap: 40px; }
		.box { width: 90px; height: 70px; background: #ffffff; }
		.round { border-radius: 18px; }
		.squircle { border-radius: 24px; corner-shape: squircle; }
		.ring { box-shadow: 0 0 0 8px #22c55e; }
		.offset { box-shadow: 10px 10px 0 #2563eb; }
		.under { box-shadow: 0 14px 0 -4px #db2777; }
		.blurred { box-shadow: 0 0 6px 6px #22c55e; }
		.inset-ring { box-shadow: inset 0 0 0 8px #22c55e; }
		.inset-offset { box-shadow: inset 10px 10px 0 #2563eb; }
		.mixed { box-shadow: inset 0 0 0 6px #2563eb, 0 0 0 6px #22c55e; }
		.inset-blurred { box-shadow: inset 0 0 10px 2px #2563eb; }
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var sheet = Css.load(CSS, "ShadowEdges.css");
		if (sheet.diagnostics.length > 0)
			Sys.println(sheet.report("ShadowEdges.css"));
		var build = () -> {
			function el(classes:Array<String>, ?children:Array<Element>):Div
				return new Div({classes: classes}, children);
			function row(shape:String, kinds:Array<String>):Div
				return el(["row"], [for (k in kinds) el(shape == "" ? ["box", k] : ["box", shape, k])]);
			var outer = ["ring", "offset", "under", "blurred"];
			var inner = ["inset-ring", "inset-offset", "mixed", "inset-blurred"];
			el(["page"], [row("", outer), row("round", outer), row("squircle", outer), row("round", inner)]);
		};
		Snapshot.scene("shadow-edges@2x", 640, 470, build, page.rgb(), page.a, 2.0);
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
