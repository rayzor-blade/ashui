package ashui.components.code;

import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Signal;

/** A command displayed above a source line. Uses the standard button behavior. **/
typedef CodeAction = {
	/** Button label. **/
	var label:String;
	/** Runs on pointer or keyboard activation. **/
	var run:Void->Void;
	/** Optional SVG icon beside the label. **/
	@:optional var icon:ashui.svg.Icon;
	/** Disables this command independently of the editor. Defaults to false. **/
	@:optional var disabled:IntoReactive<Bool>;
}

/** Commands above a zero-based source line, aligned with its indentation. **/
typedef CodeLineActions = {
	/** Source line, starting at zero. **/
	var line:Int;
	/** Commands in display order. An empty group takes no space. **/
	var actions:Array<CodeAction>;
}

/** Action metadata retained independently of the mounted editor view. **/
private class ActionPlace {
	public var offset:Int;
	public final line:Int;
	public final actions:Array<CodeAction>;

	public function new(offset:Int, line:Int, actions:Array<CodeAction>) {
		this.offset = offset;
		this.line = line;
		this.actions = actions;
	}
}

private typedef Actions = {list:Array<ActionPlace>, follow:Bool};

/** A text range and its visual decoration. **/
typedef CodeDecoration = {
	/** Start offset in the document, using the same indexing as `CodeEditor.select`; `to` is the end offset. **/
	var from:Int;
	var to:Int;
	/** CSS class for the range, such as `ui-code-squiggle-error`, `ui-code-line-current`, or an application class. **/
	var className:String;
	/** Hover text for the range. May contain multiple lines. **/
	@:optional var title:String;
	/** Decorates the full width of every touched line instead of only the specified columns. **/
	@:optional var wholeLine:Bool;
	/** Adds minimap marks on touched lines using the class `color`. **/
	@:optional var minimap:Bool;
}

/** A visual marker beside a source line in the gutter. **/
typedef CodeMarker = {
	/** Zero-based source line. **/
	var line:Int;
	/** CSS marker class, such as `ui-code-marker-breakpoint` or an application class. **/
	var className:String;
	@:optional var title:String;
	/** SVG replacing the default dot. Markers store no view or click handler. **/
	@:optional var icon:ashui.svg.SvgDocument;
	/**
		Places a marker on the boundary below the line, such as a deletion
		indicator. Leaves the regular marker slot available.
	**/
	@:optional var boundary:Bool;
	/**
		Draws a line-height strip in a separate lane at the gutter edge.
		Leaves the regular marker slot available for breakpoints or code actions.
	**/
	@:optional var bar:Bool;
	/** Adds an edge bar to the minimap using the marker class `color`. **/
	@:optional var minimap:Bool;
}

/** An element inserted between source lines. **/
typedef CodeZone = {
	/** Zero-based source line below which the zone appears. **/
	var line:Int;
	/**
		Element to display. Uses the content width after the gutter and its own
		height. The application creates the element; the editor manages its placement.
	**/
	var element:Element;
}

/** A registered zone with an edit-tracking text offset and measured height. **/
class ZonePlace {
	public var offset:Int;
	public final line:Int;
	public final element:Element;
	public var height = 0.0;
	/** Holder created when the zone is first displayed. **/
	public var view:Null<ashui.ui.Div> = null;

	public function new(offset:Int, line:Int, element:Element) {
		this.offset = offset;
		this.line = line;
		this.element = element;
	}
}

private typedef Zones = {list:Array<ZonePlace>, follow:Bool};

/** A registered marker with its source line and edit-tracking offset. **/
private typedef Place = {offset:Int, line:Int, className:String, ?title:String, ?icon:ashui.svg.SvgDocument, ?boundary:Bool, ?bar:Bool, ?minimap:Bool};

/** A minimap mark for a source line: a full-width decoration or an edge bar. **/
typedef MinimapMark = {line:Int, className:String, bar:Bool};

private typedef Decorations = {list:Array<CodeDecoration>, follow:Bool};
private typedef Markers = {list:Array<Place>, follow:Bool};

/**
	Stores editor decorations, gutter markers, actions, and zones by owner name.
	Each producer, such as compiler diagnostics or debugger breakpoints,
	replaces its own set without affecting other producers.

	Sets with `follow` track insertions and deletions. Other sets keep
	their supplied positions until the producer replaces them.
**/
class CodeAnnotations {
	/** Changes whenever annotations are replaced or moved by an edit. **/
	public final revision = Signal.make(0);

	final document:CodeDocument;
	final decorationSets = new Map<String, Decorations>();
	final markerSets = new Map<String, Markers>();
	final zoneSets = new Map<String, Zones>();
	final actionSets = new Map<String, Actions>();
	/** Owner names in registration order, which also determines drawing order. **/
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

	/** Replaces one owner's line actions. Empty clears the set; invalid lines and empty groups are ignored. **/
	public function actions(owner:String, list:Array<CodeLineActions>, follow = false):Void {
		own(owner);
		var kept:Array<ActionPlace> = [];
		for (entry in list)
			if (entry.line >= 0 && entry.line < document.lines.length && entry.actions.length > 0)
				kept.push(new ActionPlace(document.lines[entry.line].start, entry.line,
					[for (action in entry.actions) {label: action.label, run: action.run, icon: action.icon, disabled: action.disabled}]));
		if (kept.length == 0) actionSets.remove(owner);
		else actionSets.set(owner, {list: kept, follow: follow});
		touch();
	}

	/** Returns current action groups in owner registration order. Only metadata is retained here. **/
	public function actionPlaces():Array<{line:Int, actions:Array<CodeAction>}> {
		revision.get();
		var result:Array<{line:Int, actions:Array<CodeAction>}> = [];
		for (owner in owners) {
			var set = actionSets.get(owner);
			if (set != null) for (p in set.list)
				result.push({line: set.follow ? document.lineAt(p.offset) : p.line, actions: p.actions});
		}
		return result;
	}

	/** Returns current action lines for an owner, including tracked edits. **/
	public function actionLinesOf(owner:String):Array<Int> {
		var set = actionSets.get(owner);
		return set == null ? [] : [for (p in set.list) set.follow ? document.lineAt(p.offset) : p.line];
	}

	/** Replaces one owner decoration set. An empty list clears it. **/
	public function decorate(owner:String, list:Array<CodeDecoration>, follow = false):Void {
		own(owner);
		var kept = [for (d in list) {from: Std.int(Math.max(0, Math.min(d.from, d.to))), to: Std.int(Math.max(0, Math.max(d.from, d.to))), className: d.className, title: d.title, wholeLine: d.wholeLine, minimap: d.minimap}];
		if (kept.length == 0)
			decorationSets.remove(owner);
		else
			decorationSets.set(owner, {list: kept, follow: follow});
		touch();
	}

	/** Replaces one owner marker set, ignoring nonexistent lines. An empty list clears it. **/
	public function mark(owner:String, list:Array<CodeMarker>, follow = false):Void {
		own(owner);
		var kept:Array<Place> = [];
		for (m in list)
			if (m.line >= 0 && m.line < document.lines.length)
				kept.push({offset: document.lines[m.line].start, line: m.line, className: m.className, title: m.title, icon: m.icon, boundary: m.boundary, bar: m.bar, minimap: m.minimap});
		if (kept.length == 0)
			markerSets.remove(owner);
		else
			markerSets.set(owner, {list: kept, follow: follow});
		touch();
	}

	/** Replaces one owner zone set, ignoring nonexistent lines. An empty list clears it. **/
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

	/** Replaced zones awaiting removal from the editor content. **/
	var gone:Array<ZonePlace> = [];

	public function takeGone():Array<ZonePlace> {
		var taken = gone;
		gone = [];
		return taken;
	}

	/** Returns all zones in owner registration order. **/
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

	/** Returns the current source line above a zone, including tracked edits. **/
	public function zoneLine(place:ZonePlace):Int {
		for (set in zoneSets)
			if (set.list.indexOf(place) >= 0)
				return set.follow ? document.lineAt(place.offset) : place.line;
		return place.line;
	}

	/** Returns current zone lines for an owner. **/
	public function zoneLinesOf(owner:String):Array<Int> {
		var set = zoneSets.get(owner);
		return set == null ? [] : [for (p in set.list) set.follow ? document.lineAt(p.offset) : p.line];
	}

	/** Returns all decorations at their current offsets, in owner registration order. **/
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

	/** Returns decorations for an owner at their current offsets, including tracked edits. **/
	public function decorationsOf(owner:String):Array<CodeDecoration> {
		var set = decorationSets.get(owner);
		return set == null ? [] : [for (d in set.list) {from: d.from, to: d.to, className: d.className, title: d.title, wholeLine: d.wholeLine, minimap: d.minimap}];
	}

	/** Returns decorations covering an offset, including whole-line decorations on that line. **/
	public function decorationsAt(offset:Int):Array<CodeDecoration> {
		var line = document.lines[document.lineAt(offset)], end = line.start + line.text.length;
		return [for (d in decorations()) if (d.wholeLine == true ? d.from <= end && d.to >= line.start : d.from <= offset && offset < d.to) d];
	}

	function lineOf(place:Place, follow:Bool):Int
		return follow ? document.lineAt(place.offset) : place.line;

	/** Returns current marker lines for an owner, including tracked edits. **/
	public function markerLinesOf(owner:String):Array<Int> {
		var set = markerSets.get(owner);
		return set == null ? [] : [for (p in set.list) lineOf(p, set.follow)];
	}

	/** Returns whether any line needs the icon/dot column. Boundary marks and change bars use separate positions. **/
	public function hasLineMarkers():Bool {
		revision.get();
		for (set in markerSets)
			for (marker in set.list)
				if (marker.boundary != true && marker.bar != true) return true;
		return false;
	}

	/** Returns the line marker from the first registered owner, or null. **/
	public function markerAt(line:Int):Null<CodeMarker> {
		if (markerLines == null || markerLinesAt != revision.get()) {
			markerLines = new Map();
			boundaryLines = new Map();
			barLines = new Map();
			markerLinesAt = revision.get();
			for (owner in owners) {
				var set = markerSets.get(owner);
				if (set != null)
					for (p in set.list) {
						var at = lineOf(p, set.follow), into = p.boundary == true ? boundaryLines : p.bar == true ? barLines : markerLines;
						if (!into.exists(at))
							into.set(at, {line: at, className: p.className, title: p.title, icon: p.icon, boundary: p.boundary, bar: p.bar});
					}
			}
		}
		return markerLines.get(line);
	}

	var boundaryLines:Map<Int, CodeMarker> = new Map();
	var barLines:Map<Int, CodeMarker> = new Map();

	/** Returns the line change bar from the first registered owner, or null. **/
	public function barAt(line:Int):Null<CodeMarker> {
		markerAt(-1);
		return barLines.get(line);
	}

	/** Returns the boundary marker from the first registered owner, or null. **/
	public function boundaryAt(line:Int):Null<CodeMarker> {
		markerAt(-1);
		return boundaryLines.get(line);
	}

	/** Returns up to `limit` minimap marks for annotations requesting them, grouped by line and class. **/
	public function minimapMarks(limit:Int):Array<MinimapMark> {
		var seen = new Map<String, Bool>(), out:Array<MinimapMark> = [];
		function add(line:Int, className:String, bar:Bool):Void {
			var key = line + "|" + className + "|" + bar;
			if (out.length < limit && !seen.exists(key)) {
				seen.set(key, true);
				out.push({line: line, className: className, bar: bar});
			}
		}
		for (owner in owners) {
			var d = decorationSets.get(owner);
			if (d != null)
				for (x in d.list)
					if (x.minimap == true) {
						var first = document.lineAt(x.from), last = document.lineAt(Std.int(Math.max(x.from, x.to - 1)));
						for (line in first...Std.int(Math.min(last, first + 400)) + 1)
							add(line, x.className, false);
					}
			var m = markerSets.get(owner);
			if (m != null)
				for (p in m.list)
					if (p.minimap == true)
						add(lineOf(p, m.follow), p.className, true);
		}
		return out;
	}

	/** Moves edit-tracking annotations from the old text positions to the new text positions. **/
	public function edited(before:String, after:String):Void {
		var following = false;
		for (set in decorationSets)
			following = following || set.follow;
		for (set in markerSets)
			following = following || set.follow;
		for (set in zoneSets)
			following = following || set.follow;
		for (set in actionSets)
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
					kept.push({from: from, to: Std.int(Math.max(from, to)), className: d.className, title: d.title, wholeLine: d.wholeLine, minimap: d.minimap});
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
		for (set in actionSets)
			if (set.follow)
				for (p in set.list)
					p.offset = move(p.offset, true);
		touch();
	}
}
