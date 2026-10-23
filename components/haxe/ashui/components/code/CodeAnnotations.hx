package ashui.components.code;

import ashui.layout.Element;
import ashui.reactive.Signal;

/** A range of the text to mark, and how. **/
typedef CodeDecoration = {
	/** The range, as offsets into the text, as `CodeEditor.select` takes them. **/
	var from:Int;
	var to:Int;
	/** A CSS class, which makes the range look as it should: `ui-code-squiggle-error`, `ui-code-line-current` or the app's own. **/
	var className:String;
	/** What the range says, for a hover; it may run over several lines. **/
	@:optional var title:String;
	/** Paints the full width of each line the range touches, not only the range's own columns. **/
	@:optional var wholeLine:Bool;
}

/** An element in the gutter beside a line. **/
typedef CodeMarker = {
	/** The line, from 0 as `CodeEditor.toggleFold` counts. **/
	var line:Int;
	/** A CSS class: `ui-code-marker-breakpoint` or the app's own. **/
	var className:String;
	@:optional var title:String;
	/** An SVG in place of the default dot; no view or click handler is kept with a marker. **/
	@:optional var icon:ashui.svg.SvgDocument;
}

/** An element placed between two lines. **/
typedef CodeZone = {
	/** The line the zone goes below, from 0; the zone is between it and the next line. **/
	var line:Int;
	/** What is shown there. It takes the editor's content width, less the gutter, and its own height; the app made it and owns what it reads. **/
	var element:Element;
}

/** A zone as kept: where it is in the text, which `follow` moves, and the height its element measured. **/
class ZonePlace {
	public var offset:Int;
	public final line:Int;
	public final element:Element;
	public var height = 0.0;
	/** The element's holder in the editor, made when the zone is first drawn. **/
	public var view:Null<ashui.ui.Div> = null;

	public function new(offset:Int, line:Int, element:Element) {
		this.offset = offset;
		this.line = line;
		this.element = element;
	}
}

private typedef Zones = {list:Array<ZonePlace>, follow:Bool};

/** A marker as kept: where it is in the text, which `follow` moves, and the line it was given. **/
private typedef Place = {offset:Int, line:Int, className:String, ?title:String, ?icon:ashui.svg.SvgDocument};

private typedef Decorations = {list:Array<CodeDecoration>, follow:Bool};
private typedef Markers = {list:Array<Place>, follow:Bool};

/**
	What an app marks in an editor's text and gutter, in sets by owner name: a
	producer, such as a compiler's problems or a debugger's breakpoints,
	replaces its own set and leaves the others as they are.

	A set made to `follow` the edits moves with the text it was set on: its
	offsets shift with insertions and deletions before them, as a breakpoint
	stays with its line. Another set is kept as given, for its producer to send
	again after a change.
**/
class CodeAnnotations {
	/** Moves when any set is replaced or follows an edit; what is drawn from the sets follows it. **/
	public final revision = Signal.make(0);

	final document:CodeDocument;
	final decorationSets = new Map<String, Decorations>();
	final markerSets = new Map<String, Markers>();
	final zoneSets = new Map<String, Zones>();
	/** The owners in the order their sets were first given, which is the order they are drawn in. **/
	final owners:Array<String> = [];
	var markerLines:Null<Map<Int, CodeMarker>> = null;
	var markerLinesAt = -1;

	public function new(document:CodeDocument)
		this.document = document;

	function touch():Void
		revision.set(revision.get() + 1);

	function own(owner:String):Void
		if (owners.indexOf(owner) < 0)
			owners.push(owner);

	/** Replaces `owner`'s decorations with `list`; an empty list clears them. **/
	public function decorate(owner:String, list:Array<CodeDecoration>, follow = false):Void {
		own(owner);
		var kept = [for (d in list) {from: Std.int(Math.max(0, Math.min(d.from, d.to))), to: Std.int(Math.max(0, Math.max(d.from, d.to))), className: d.className, title: d.title, wholeLine: d.wholeLine}];
		if (kept.length == 0)
			decorationSets.remove(owner);
		else
			decorationSets.set(owner, {list: kept, follow: follow});
		touch();
	}

	/** Replaces `owner`'s markers with `list`, dropping a line the document does not have; an empty list clears them. **/
	public function mark(owner:String, list:Array<CodeMarker>, follow = false):Void {
		own(owner);
		var kept:Array<Place> = [];
		for (m in list)
			if (m.line >= 0 && m.line < document.lines.length)
				kept.push({offset: document.lines[m.line].start, line: m.line, className: m.className, title: m.title, icon: m.icon});
		if (kept.length == 0)
			markerSets.remove(owner);
		else
			markerSets.set(owner, {list: kept, follow: follow});
		touch();
	}

	/** Replaces `owner`'s zones with `list`, dropping a line the document does not have; an empty list clears them. **/
	public function zone(owner:String, list:Array<CodeZone>, follow = false):Void {
		own(owner);
		var kept:Array<ZonePlace> = [];
		for (z in list)
			if (z.line >= 0 && z.line < document.lines.length)
				kept.push(new ZonePlace(document.lines[z.line].start, z.line, z.element));
		var old = zoneSets.get(owner);
		if (kept.length == 0)
			zoneSets.remove(owner);
		else
			zoneSets.set(owner, {list: kept, follow: follow});
		// What was there and is not now is taken out of the editor by whoever draws the zones.
		gone = gone.concat(old == null ? [] : [for (p in old.list) if (kept.indexOf(p) < 0) p]);
		touch();
	}

	/** Zones replaced or cleared since they were last asked for, which the editor must take out of its content. **/
	var gone:Array<ZonePlace> = [];

	public function takeGone():Array<ZonePlace> {
		var taken = gone;
		gone = [];
		return taken;
	}

	/** Every zone, owner by owner. **/
	public function zonePlaces():Array<ZonePlace> {
		var all:Array<ZonePlace> = [];
		for (owner in owners) {
			var set = zoneSets.get(owner);
			if (set != null)
				for (p in set.list)
					all.push(p);
		}
		return all;
	}

	/** The line a zone is below now, which a set that follows the edits has moved. **/
	public function zoneLine(place:ZonePlace):Int {
		for (set in zoneSets)
			if (set.list.indexOf(place) >= 0)
				return set.follow ? document.lineAt(place.offset) : place.line;
		return place.line;
	}

	/** `owner`'s zones' lines now. **/
	public function zoneLinesOf(owner:String):Array<Int> {
		var set = zoneSets.get(owner);
		return set == null ? [] : [for (p in set.list) set.follow ? document.lineAt(p.offset) : p.line];
	}

	/** Every decoration, owner by owner, at its current offsets. **/
	public function decorations():Array<CodeDecoration> {
		var all:Array<CodeDecoration> = [];
		for (owner in owners) {
			var set = decorationSets.get(owner);
			if (set != null)
				for (d in set.list)
					all.push(d);
		}
		return all;
	}

	/** `owner`'s decorations at their current offsets, which a set that follows the edits has moved. **/
	public function decorationsOf(owner:String):Array<CodeDecoration> {
		var set = decorationSets.get(owner);
		return set == null ? [] : [for (d in set.list) {from: d.from, to: d.to, className: d.className, title: d.title, wholeLine: d.wholeLine}];
	}

	/** The decorations over `offset`: a range with it inside, or a whole-line one on its line. **/
	public function decorationsAt(offset:Int):Array<CodeDecoration> {
		var line = document.lines[document.lineAt(offset)], end = line.start + line.text.length;
		return [for (d in decorations()) if (d.wholeLine == true ? d.from <= end && d.to >= line.start : d.from <= offset && offset < d.to) d];
	}

	function lineOf(place:Place, follow:Bool):Int
		return follow ? document.lineAt(place.offset) : place.line;

	/** `owner`'s markers' lines now, which a set that follows the edits has moved. **/
	public function markerLinesOf(owner:String):Array<Int> {
		var set = markerSets.get(owner);
		return set == null ? [] : [for (p in set.list) lineOf(p, set.follow)];
	}

	/** The marker on `line`, from the first owner that has one there. **/
	public function markerAt(line:Int):Null<CodeMarker> {
		if (markerLines == null || markerLinesAt != revision.get()) {
			markerLines = new Map();
			markerLinesAt = revision.get();
			for (owner in owners) {
				var set = markerSets.get(owner);
				if (set != null)
					for (p in set.list) {
						var at = lineOf(p, set.follow);
						if (!markerLines.exists(at))
							markerLines.set(at, {line: at, className: p.className, title: p.title, icon: p.icon});
					}
			}
		}
		return markerLines.get(line);
	}

	/** Moves what follows the edits for the text having changed from `before` to `after`. **/
	public function edited(before:String, after:String):Void {
		var following = false;
		for (set in decorationSets)
			following = following || set.follow;
		for (set in markerSets)
			following = following || set.follow;
		for (set in zoneSets)
			following = following || set.follow;
		if (!following || before == after)
			return;
		// The one replaced stretch: what both texts share at the start and at the end is left out.
		var shortest = Std.int(Math.min(before.length, after.length)), start = 0, tail = 0;
		while (start < shortest && before.charCodeAt(start) == after.charCodeAt(start))
			start++;
		while (tail < shortest - start && before.charCodeAt(before.length - 1 - tail) == after.charCodeAt(after.length - 1 - tail))
			tail++;
		var oldEnd = before.length - tail, newEnd = after.length - tail;
		// A stretch replaced by another with lines in it, as a file read again is, is compared by lines, so a line both texts have keeps its place.
		var lines = start < oldEnd && start < newEnd && (before.substring(start, oldEnd).indexOf("\n") >= 0 || after.substring(start, newEnd).indexOf("\n") >= 0) ? CodeLineDiff.of(before,
			after, start, oldEnd, newEnd) : null;
		// An offset inside the replaced text goes to its line's place, or to its start; one at an insertion goes after it when `right`, so a start stays with the text after it.
		function move(offset:Int, right:Bool):Int {
			if (offset < start)
				return offset;
			if (offset > oldEnd)
				return offset - oldEnd + newEnd;
			if (offset == oldEnd && (oldEnd > start || right))
				return newEnd;
			var mapped = lines == null ? -1 : lines.map(offset);
			return mapped >= 0 ? mapped : start;
		}
		var emptied = [];
		for (owner => set in decorationSets)
			if (set.follow) {
				var kept = [];
				for (d in set.list) {
					var from = move(d.from, true), to = move(d.to, false);
					// A range whose text went is gone with it, except a line's, which is still its line.
					if (to <= from && d.to > d.from && d.wholeLine != true)
						continue;
					kept.push({from: from, to: Std.int(Math.max(from, to)), className: d.className, title: d.title, wholeLine: d.wholeLine});
				}
				if (kept.length == 0)
					emptied.push(owner);
				else
					set.list = kept;
			}
		for (owner in emptied)
			decorationSets.remove(owner);
		for (set in markerSets)
			if (set.follow)
				for (p in set.list)
					p.offset = move(p.offset, true);
		for (set in zoneSets)
			if (set.follow)
				for (p in set.list)
					p.offset = move(p.offset, true);
		touch();
	}
}
