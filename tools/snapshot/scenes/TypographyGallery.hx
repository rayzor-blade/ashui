import ashui.components.Typography;
import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Long-form text in a prose block, after shadcn's typography page: a title
	and lead, sections under headings, a quotation, a list, inline code and
	a table; then a lead, a large statement, small print and a muted
	remark on their own. Writes `.ashui/snapshots/typography.png`
	(`typography-light` with `SCHEME=light`).
**/
class TypographyGallery {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		var build = () -> hxx('
			<div flexDirection={Column} padding={48} gap={48} width={800}>
				<prose>
					<h1>The Joke Tax Chronicles</h1>
					<lead>Once upon a time, in a far-off land, there was a very lazy king who spent all day lounging on his throne.</lead>
					<p>One day, his advisors came to him with a problem: the kingdom was running out of money.</p>
					<h2>The King\'s Plan</h2>
					<p>The king thought long and hard, and finally came up with <a>a brilliant plan</a>: he would tax the jokes in the kingdom.</p>
					<blockquote><p>"After all," he said, "everyone enjoys a good joke, so it\'s only fair that they should pay for the privilege."</p></blockquote>
					<h3>The Joke Tax</h3>
					<p>The king\'s subjects were not amused. They grumbled and complained, but the king was firm:</p>
					<ul>
						<li>1st level of puns: 5 gold coins</li>
						<li>2nd level of jokes: 10 gold coins</li>
						<li>3rd level of one-liners: 20 gold coins</li>
					</ul>
					<p>As a result, people stopped telling jokes, and the kingdom fell into a gloom. The <code>tax.collect()</code> call ran every morning.</p>
					<h4>People stopped telling jokes</h4>
					<table>
						<thead><tr><th>King\'s Treasury</th><th>People\'s happiness</th></tr></thead>
						<tbody>
							<tr><td>Empty</td><td>Overflowing</td></tr>
							<tr><td>Modest</td><td>Satisfied</td></tr>
							<tr><td>Full</td><td>Ecstatic</td></tr>
						</tbody>
					</table>
				</prose>
				<div flexDirection={Column} gap={16}>
					<lead>A modal dialog that interrupts the user with important content.</lead>
					<large>Are you absolutely sure?</large>
					<small>Email address</small>
					<muted>Enter your email address.</muted>
				</div>
			</div>
		');
		Snapshot.scene(light ? "typography-light" : "typography", 800, 1700, build, page.rgb(), page.a, 2.0, 1.0);
	}
}
