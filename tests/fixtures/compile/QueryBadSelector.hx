// expect: query: bad selector ".row >"
import ashui.layout.LayoutTree;
import ashui.ui.Query.query;

class QueryBadSelector {
	static function main() {
		query(".row >", new LayoutTree());
	}
}
