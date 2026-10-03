import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Stage 4's built-in elements: text, password, search and number inputs
	with a placeholder, a range, progress (one indeterminate), meters in
	each of their three judgements, a fieldset with a legend, one disabled,
	a link, a rule and an output.
**/
class Forms {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var name = Signal.make("Ada Lovelace");
		var secret = Signal.make("hunter2");
		var amount = Signal.make(3.0);
		var volume = Signal.make(30.0);
		var build = () -> hxx('
			<div flexDirection={Row} padding={24} gap={24} width={640} height={420}>
				<div flexDirection={Column} alignItems={Start} gap={10}>
					<fieldset>
						<legend>Account</legend>
						<label>Name <input type="text" value={name} /></label>
						<input type="password" value={secret} />
						<input type="search" placeholder="Search" />
						<input type="number" valueAsNumber={amount} min={0} max={10} />
					</fieldset>
					<fieldset disabled={true}>
						<legend>Disabled</legend>
						<input type="text" placeholder="Nothing to type" />
						<label><input type="checkbox" checked={true} />Held</label>
					</fieldset>
				</div>
				<div flexDirection={Column} alignItems={Start} gap={12}>
					<input type="range" valueAsNumber={volume} />
					<progress value={0.6} />
					<progress />
					<meter value={0.2} />
					<meter value={0.5} low={0.3} high={0.7} optimum={0.1} />
					<meter value={0.9} low={0.3} high={0.7} optimum={0.1} />
					<hr />
					<p>Read the <a href="https://haxe.org">manual</a> first.</p>
					<p>Total: <output>42</output></p>
				</div>
			</div>
		');
		Snapshot.scene("forms@2x", 640, 420, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
