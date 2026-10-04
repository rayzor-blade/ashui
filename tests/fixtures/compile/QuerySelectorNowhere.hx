// expect: query: a selector needs where to look
import ashui.ui.Query.query;

class QuerySelectorNowhere {
	static function main() {
		query("#save");
	}
}
