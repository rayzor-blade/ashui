import ashui.core.render.Snapshot;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Stage 5's built-in elements: a bulleted list with a list inside it, a
	numbered list counting in roman numerals from 4, a table with a
	caption, a header, a spanning cell and a column of fixed width, a
	preformatted block and a quotation.
**/
class Content {
	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var page = ThemeState.get().color(Background);
		var source = "function greet(name) {\n    return 'hello, ' + name;\n}";
		var build = () -> hxx('
			<div flexDirection={Row} padding={24} gap={28} width={720} height={460}>
				<div flexDirection={Column} width={260}>
					<ul>
						<li>Fruit
							<ul><li>Apples</li><li>Pears<ul><li>Conference</li></ul></li></ul>
						</li>
						<li>Bread</li>
					</ul>
					<ol start={4} type="I"><li>Fourth</li><li>Fifth</li><li value={9}>Ninth</li></ol>
					<pre>{source}</pre>
					<blockquote><p>Simple things should be simple.</p></blockquote>
				</div>
				<div flexDirection={Column} width={380} gap={16}>
					<table>
						<caption>Orders</caption>
						<colgroup><col width="60" /><col /><col width="2*" /></colgroup>
						<thead><tr><th>No.</th><th>Item</th><th>Note</th></tr></thead>
						<tbody>
							<tr><td>1</td><td>Pears</td><td>Ripe</td></tr>
							<tr><td>2</td><td colspan={2}>Out of stock until Friday</td></tr>
						</tbody>
						<tfoot><tr><td>2</td><td>items</td><td></td></tr></tfoot>
					</table>
					<dl><dt>Ripe</dt><dd>Soft at the stem.</dd><dt>Firm</dt><dd>A day or two more.</dd></dl>
				</div>
			</div>
		');
		Snapshot.scene("content@2x", 720, 460, build, page.rgb(), page.a, 2.0);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
