import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	A form submitted while invalid: its required email and checkbox marked
	:user-invalid in the theme's error colours, the email focused, its ring
	grown in the error ring colour; frame 0 before, frame 12 after.
**/
class FormCheck {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var form:Null<ashui.ui.Form> = null;
		var build = () -> {
			form = new ashui.ui.Form({}, [
				hxx('<input type="email" name="email" required={true} placeholder="you@example.com" />'),
				hxx('<label><input type="checkbox" name="agree" required={true} />I agree</label>'),
				hxx('<button>Send</button>')
			]);
			hxx('<div flexDirection={Column} padding={24} gap={12} width={320} height={220}>{form}</div>');
		};
		Snapshot.sequence("formcheck", 320, 220, build, 60, 13, (frame, tree, root) -> if (frame == 1) form.requestSubmit(), page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
