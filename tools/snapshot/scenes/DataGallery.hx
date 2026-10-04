import ashui.components.Breadcrumb;
import ashui.components.Kbd;
import ashui.components.Pagination;
import ashui.components.Table;
import ashui.core.render.Snapshot;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style;
import ashui.ui.Hxx.hxx;

/**
	Breadcrumbs, pagination, a table and keycaps, section by section. Dark
	by default; `SCHEME=light` renders the light scheme.
**/
class DataGallery {
	static function main() {
		var light = Sys.getEnv("SCHEME") == "light";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var page = ThemeState.get().color(Background);
		ashui.css.Css.load('h2 { font-size: 20px; font-weight: 700; color: var(--text-primary); margin: 0 }');
		var build = () -> hxx('
			<div flexDirection={Column} padding={48} gap={40} width={1200} height={1250}>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-8">
					<h2>Breadcrumb</h2>
					<breadcrumb><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item>Products</breadcrumb-item><breadcrumb-item>Electronics</breadcrumb-item><breadcrumb-item current={true}>Laptop</breadcrumb-item></breadcrumb>
					<breadcrumb separator="/"><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item>Documents</breadcrumb-item><breadcrumb-item current={true}>Current Project</breadcrumb-item></breadcrumb>
					<breadcrumb size={Sm}><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item current={true}>Small</breadcrumb-item></breadcrumb>
					<breadcrumb size={Lg}><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item current={true}>Large</breadcrumb-item></breadcrumb>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-8">
					<h2>Pagination</h2>
					<pagination total={10} />
					<pagination total={50} page={5} edges={true} />
					<div flexDirection={Row} gap={48} alignItems={Center}><pagination total={5} size={Sm} /><pagination total={5} size={Lg} /></div>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-8">
					<h2>Table</h2>
					<table>
						<table-caption>A list of your recent invoices.</table-caption>
						<table-header><table-row><table-head>Invoice</table-head><table-head>Status</table-head><table-head>Method</table-head><table-head>Amount</table-head></table-row></table-header>
						<table-body>
							<table-row><table-cell>INV001</table-cell><table-cell>Paid</table-cell><table-cell>Credit Card</table-cell><table-cell>$$250.00</table-cell></table-row>
							<table-row selected={true}><table-cell>INV002</table-cell><table-cell>Pending</table-cell><table-cell>PayPal</table-cell><table-cell>$$150.00</table-cell></table-row>
							<table-row><table-cell>INV003</table-cell><table-cell>Unpaid</table-cell><table-cell>Bank Transfer</table-cell><table-cell>$$350.00</table-cell></table-row>
						</table-body>
						<table-footer><table-row><table-cell colspan={3}>Total</table-cell><table-cell>$$750.00</table-cell></table-row></table-footer>
					</table>
				</div>
				<div class="bg-surface border border-border rounded-xl p-4 flex-col gap-8">
					<h2>Kbd</h2>
					<div flexDirection={Row} gap={8} alignItems={Center}><kbd>Ctrl</kbd><kbd>K</kbd><kbd size={Sm}>Esc</kbd><kbd size={Lg}>Enter</kbd></div>
				</div>
			</div>
		');
		Snapshot.scene(light ? "data-light" : "data", 1200, 1250, build, page.rgb(), page.a, 2.0, 0.3);
		for (p in ashui.css.Css.problems)
			Sys.println("css: " + p);
	}
}
