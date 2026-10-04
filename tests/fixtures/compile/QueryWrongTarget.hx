// expect: query takes an element, a Ref, or a selector and where to look, not Int
import ashui.ui.Query.query;

class QueryWrongTarget {
	static function main() {
		query(42);
	}
}
