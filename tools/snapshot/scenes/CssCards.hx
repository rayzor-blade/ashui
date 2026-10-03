import ashui.core.render.Snapshot;
import ashui.css.Css;
import ashui.layout.Element;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Text;

/**
	A page styled by a stylesheet alone: the elements carry classes and no
	style of their own. Cards from one rule, a featured one by a second
	class, striped rows by :nth-child, a last row by :last-child, colours
	from :root's custom properties, a gradient, shadows, a turned badge and
	text that takes its size and weight from the card around it. Rendered at
	one and two image pixels per layout unit.
**/
class CssCards {
	static final CSS = '
		:root {
			--ink: #0f172a;
			--muted: #64748b;
			--accent: #6366f1;
			--card: #ffffff;
		}
		.page { flex-direction: row; gap: 20px; padding: 24px; width: 640px; height: 320px; background: #f1f5f9; }
		.card {
			flex-direction: column; gap: 8px; padding: 16px; width: 180px;
			background: var(--card); border-radius: 16px;
			box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08), 0 8px 24px rgba(15, 23, 42, 0.08);
			font-size: 13px; color: var(--muted);
		}
		.card.featured {
			background: linear-gradient(135deg, #6366f1, #a855f7);
			color: white;
			transform: translateY(-6px);
			box-shadow: 0 12px 32px rgba(99, 102, 241, 0.45);
		}
		.title { font-size: 18px; font-weight: 700; color: var(--ink); }
		.featured .title { color: white; }
		.row { height: 26px; padding: 4px 8px; border-radius: 6px; align-items: center; }
		.row:nth-child(odd) { background: rgba(99, 102, 241, 0.08); }
		.featured .row:nth-child(odd) { background: rgba(255, 255, 255, 0.18); }
		.row:last-child { border: 1px solid var(--accent); }
		.badge {
			align-self: flex-start; padding: 2px 8px; border-radius: 9999px;
			background: var(--accent); color: white; font-size: 11px; font-weight: 600;
			transform: rotate(-4deg);
		}
	';

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var sheet = Css.load(CSS, "CssCards.css");
		if (sheet.diagnostics.length > 0)
			Sys.println(sheet.report("CssCards.css"));
		var build = () -> {
			function el(classes:Array<String>, ?children:Array<Element>):Div
				return new Div({classes: classes}, children);
			function card(title:String, featured:Bool):Div {
				var rows:Array<Element> = [for (i in 1...5) el(["row"], [new Text('Item $i')])];
				var kids:Array<Element> = [el(["badge"], [new Text(featured ? "Featured" : "Plan")]), el(["title"], [new Text(title)])];
				return el(featured ? ["card", "featured"] : ["card"], kids.concat(rows));
			}
			el(["page"], [card("Starter", false), card("Pro", true), card("Team", false)]);
		};
		Snapshot.scene("css-cards", 640, 320, build, page.rgb(), page.a);
		Snapshot.scene("css-cards@2x", 640, 320, build, page.rgb(), page.a, 2.0);
		for (p in Css.problems)
			Sys.println("css: " + p);
	}
}
