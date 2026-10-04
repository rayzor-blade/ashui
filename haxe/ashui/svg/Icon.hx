package ashui.svg;

/**
	An icon as a prop takes one: a document read at compile time,
	`SvgDocument.of(<svg ...>...</svg>)`, or SVG markup in a string, read
	the first time it is given and kept for the next.
**/
@:forward
abstract Icon(SvgDocument) from SvgDocument to SvgDocument {
	static final read = new Map<String, SvgDocument>();

	@:from public static function fromMarkup(markup:String):Icon {
		var doc = read.get(markup);
		if (doc == null)
			read.set(markup, doc = SvgDocument.parse(markup));
		return doc;
	}
}
