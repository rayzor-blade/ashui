package ashui.components;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.components.Select.SelectItem;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;
import ashui.ui.For;

/** Calendar date with a year, zero-based month (0–11), and day of the month. **/
typedef CalendarDay = {year:Int, month:Int, day:Int};

typedef CalendarProps = {
	/** Selected date, or null. A supplied signal is read and updated; a constant sets the initial selection. **/
	?value:IntoReactive<Null<CalendarDay>>,
	/** Date marked as today. Defaults to the current system date. **/
	?today:CalendarDay,
	/** First weekday: 0 for Sunday (default), 1 for Monday. **/
	?weekStart:Int,
	/** Earliest year available for navigation and selection, inclusive. **/
	?minYear:Int,
	/** Latest year available for navigation and selection, inclusive. **/
	?maxYear:Int,
	?onChange:CalendarDay->Void,
	?id:String
}

/**
	A date picker with month/year selects, previous/next navigation and a
	six-week day grid. Adjacent-month days are muted. Today is marked, and
	the selected day is filled. Selecting an adjacent-month day navigates
	to that month; month changes use a sliding transition.

	Keyboard controls: arrows move by day or week; Page Up/Down change month;
	Home/End move to the week's ends; Enter/Space select the focused day.

	CSS parts: `.ui-calendar`, `-header`, `-caption`, `-month-picker`,
	`-year-picker`, `-nav`, `-body`, `-weekdays`, `-weekday`, `-months`,
	`-grid` and `-day`. All suffixes use the `ui-calendar` prefix.
	Navigation exposes `[data-step]`. Month grids use `[data-enter]` and
	`[data-leaving]` with `next` or `prev`. Days expose `[data-outside]`,
	`[data-today]`, `[data-selected]`, `:hover` and `:focus-visible`.
**/
class Calendar extends Component<CalendarProps> {
	public var value(default, null):Signal<Null<CalendarDay>>;

	static final MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
	static final WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];
	static final ARROWS = [
		"prev" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>),
		"next" => ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>)
	];

	function render():Element {
		var minYear = props.minYear, maxYear = props.maxYear;
		if (minYear != null && maxYear != null && minYear > maxYear)
			throw "Calendar minYear must not exceed maxYear";
		function allowed(year:Int):Bool
			return (minYear == null || year >= minYear) && (maxYear == null || year <= maxYear);
		function clampYear(year:Int):Int
			return minYear != null && year < minYear ? minYear : maxYear != null && year > maxYear ? maxYear : year;
		value = switch props.value {
			case null: Signal.make((null : Null<CalendarDay>));
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var now = Date.now();
		var today = props.today != null ? props.today : {year: now.getFullYear(), month: now.getMonth(), day: now.getDate()};
		var start = props.weekStart == null ? 0 : props.weekStart;
		var v = value;
		var initial = v.get() != null ? v.get() : today;
		var initialYear = clampYear(initial.year);
		var initialDays = DateTools.getMonthDays(new Date(initialYear, initial.month, 1, 0, 0, 0));
		var first = {year: initialYear, month: initial.month, day: Std.int(Math.min(initial.day, initialDays))};
		// The month shown, and the day the keys are on.
		var shown = Signal.make({year: first.year, month: first.month});
		var focused = Signal.make(key(first));

		// The months on screen: the one shown, and one leaving while it slides away.
		var pages = Signal.make([new Page(first.year, first.month, null)]);
		// Turns to `m`, the new month sliding in from the side it is on and the one shown sliding out the other.
		function turn(m:{year:Int, month:Int}) {
			if (!allowed(m.year))
				return;
			var now = shown.get();
			if (m.year == now.year && m.month == now.month)
				return;
			var side = m.year * 12 + m.month > now.year * 12 + now.month ? "next" : "prev";
			shown.set(m);
			var leaving = Lambda.find(pages.get(), p -> p.leaving.get() == null);
			pages.set(pages.get().concat([new Page(m.year, m.month, side)]));
			if (leaving == null)
				return;
			leaving.leaving.set(side);
			var theme = ashui.theme.ThemeState.tryGet();
			var seconds = theme == null ? 0 : theme.animations().durationFaster / 1000;
			var identity = leaving.element == null ? null : ashui.css.Identity.of(leaving.element.tree, leaving.element.node.id);
			ashui.css.Animations.whenPlayed([identity], seconds, () -> pages.set(pages.get().filter(p -> p != leaving)));
		}
		// Keep the date the keys are on in the month picked, without choosing a day.
		function jump(m:{year:Int, month:Int}) {
			if (!allowed(m.year))
				return;
			var at = parse(focused.get());
			var days = DateTools.getMonthDays(new Date(m.year, m.month, 1, 0, 0, 0));
			focused.set(key({year: m.year, month: m.month, day: Std.int(Math.min(at.day, days))}));
			turn(m);
		}
		var pickedMonth = Signal.make(Std.string(first.month));
		var pickedYear = Signal.make(Std.string(first.year));
		new Watch(() -> shown.get(), m -> {
			pickedMonth.set(Std.string(m.month));
			pickedYear.set(Std.string(m.year));
		});
		var monthOptions:Array<Element> = [for (i in 0...12) new SelectItem({value: Std.string(i)}, [new ashui.ui.Text(MONTHS[i])])];
		var monthPicker = new Select({value: pickedMonth, onChange: month -> jump({year: shown.get().year, month: Std.parseInt(month)})}, monthOptions);
		var monthIdentity = ashui.css.Identity.of(monthPicker.tree, monthPicker.node.id);
		monthIdentity.addClasses(["ui-calendar-month-picker"]);
		monthIdentity.setAttribute("aria-label", "Month");
		// Recenter the year list if navigation reaches either end of its 201-year window.
		function windowStart(year:Int):Int {
			var at = year - 100;
			if (minYear != null)
				at = Std.int(Math.max(at, minYear));
			if (maxYear != null)
				at = Std.int(Math.min(at, maxYear - 200));
			if (minYear != null)
				at = Std.int(Math.max(at, minYear));
			return at;
		}
		var yearStart = Signal.make(windowStart(first.year));
		new Watch(() -> shown.get().year, year -> if (year < yearStart.get() || year > yearStart.get() + 200) yearStart.set(windowStart(year)));
		var yearPicker = new For(() -> [yearStart.get()], startYear -> {
			var count = maxYear == null ? 201 : Std.int(Math.min(201, maxYear - startYear + 1));
			var options:Array<Element> = [for (i in 0...count) new SelectItem({value: Std.string(startYear + i)}, [new ashui.ui.Text(Std.string(startYear + i))])];
			var picker = new Select({value: pickedYear, virtualRowHeight: 33, onChange: year -> jump({year: Std.parseInt(year), month: shown.get().month})}, options);
			var identity = ashui.css.Identity.of(picker.tree, picker.node.id);
			identity.addClasses(["ui-calendar-year-picker"]);
			identity.setAttribute("aria-label", "Year");
			picker;
		});
		var caption = Library.part("ui-calendar-caption", null, null, [monthPicker, yearPicker]);
		var header = Library.part("ui-calendar-header", null, null,
			[nav("prev", () -> turn(shift(shown.get(), -1)), Computed.make(() -> !allowed(shift(shown.get(), -1).year))), caption,
				nav("next", () -> turn(shift(shown.get(), 1)), Computed.make(() -> !allowed(shift(shown.get(), 1).year)))]);
		var weekdays = Library.part("ui-calendar-weekdays", null, null,
			[for (i in 0...7) Library.part("ui-calendar-weekday", null, null, [new ashui.ui.Text(WEEKDAYS[(i + start) % 7])])]);

		var choose = (d:CalendarDay) -> {
			if (!allowed(d.year))
				return;
			v.set(d);
			turn({year: d.year, month: d.month});
			focused.set(key(d));
			if (props.onChange != null)
				props.onChange(d);
		};
		var months = Library.part("ui-calendar-months", null, null, [new For(() -> pages.get(), page -> {
			var lead = (new Date(page.year, page.month, 1, 0, 0, 0).getDay() - start + 7) % 7;
			var cells:Array<Element> = [for (i in 0...42) {
				var d = addDays({year: page.year, month: page.month, day: 1}, i - lead);
				var k = key(d);
				var cell = Library.part("ui-calendar-day", "button", [
					"outside" => (d.month != page.month ? "" : null : Null<String>),
					"today" => (same(d, today) ? "" : null : Null<String>),
					"selected" => Computed.make(() -> (v.get() != null && same(v.get(), d) ? "" : null : Null<String>))
				], [new ashui.ui.Text(Std.string(d.day))]);
				ashui.css.Identity.of(cell.tree, cell.node.id).setAttribute("type", "button");
				var i = Interaction.of(cell.node).setFocusable(true);
				if (!allowed(d.year))
					i.setDisabled(true);
				i.onClick(_ -> choose(d));
				// Focus follows the day the keys are on, while focus is in the days, or was as the month turned; a leaving month's days let it go.
				new Watch(() -> focused.get(), f -> if (f == k && page.leaving.get() == null && body != null && (refocus || hasFocusIn(body))) {
					refocus = false;
					Focus.set(i, true);
				});
				cell;
			}];
			page.element = Library.part("ui-calendar-grid", null, ["enter" => page.enter, "leaving" => Computed.make(() -> page.leaving.get())], cells);
			page.element;
		})]);
		body = Library.part("ui-calendar-body", null, null, [weekdays, months]);
		Interaction.of(body.node).onKeyDown(e -> {
			var at = parse(focused.get());
			var next:Null<CalendarDay> = switch e.key {
				case Named(ArrowLeft): addDays(at, -1);
				case Named(ArrowRight): addDays(at, 1);
				case Named(ArrowUp): addDays(at, -7);
				case Named(ArrowDown): addDays(at, 7);
				case Named(PageUp): monthOver(at, -1);
				case Named(PageDown): monthOver(at, 1);
				case Named(Home): addDays(at, -((dayOfWeek(at) - start + 7) % 7));
				case Named(End): addDays(at, 6 - ((dayOfWeek(at) - start + 7) % 7));
				case _: null;
			}
			if (next == null)
				return;
			e.preventDefault();
			if (!allowed(next.year))
				return;
			if (next.month != shown.get().month || next.year != shown.get().year) {
				// The month's days are made anew; the focused one takes focus as it is made.
				refocus = true;
				turn({year: next.year, month: next.month});
			}
			focused.set(key(next));
		});
		return Library.part("ui-calendar", null, null, [header, body], props.id);
	}

	var body:Null<ashui.ui.Div> = null;
	/** Requests focus on the new day cell after keyboard navigation changes the month. **/
	var refocus = false;

	function nav(kind:String, run:Void->Void, disabled:IntoReactive<Bool>):Element {
		var b = Library.part("ui-calendar-nav", "button", ["step" => kind], [new ashui.ui.Svg(ARROWS.get(kind), {width: 16, height: 16})]);
		ashui.css.Identity.of(b.tree, b.node.id).setAttribute("type", "button");
		Interaction.of(b.node).setFocusable(true).setDisabled(disabled).onClick(_ -> run());
		return b;
	}

	static function hasFocusIn(box:ashui.ui.Div):Bool {
		var f = Focus.of(box.tree);
		return f != null && (f.node.id == box.node.id || box.tree.ancestors(f.node.id).indexOf(box.node.id) >= 0);
	}

	static function key(d:CalendarDay):String
		return '${d.year}-${d.month}-${d.day}';

	static function parse(k:String):CalendarDay {
		var p = k.split("-");
		return {year: Std.parseInt(p[0]), month: Std.parseInt(p[1]), day: Std.parseInt(p[2])};
	}

	static function same(a:CalendarDay, b:CalendarDay):Bool
		return a.year == b.year && a.month == b.month && a.day == b.day;

	static function dayOfWeek(d:CalendarDay):Int
		return new Date(d.year, d.month, d.day, 0, 0, 0).getDay();

	/** Adds days across month and year boundaries. Uses midday to avoid date shifts at daylight-saving transitions. **/
	static function addDays(d:CalendarDay, n:Int):CalendarDay {
		var t = new Date(d.year, d.month, d.day, 12, 0, 0).getTime() + n * 86400000.0;
		var r = Date.fromTime(t);
		return {year: r.getFullYear(), month: r.getMonth(), day: r.getDate()};
	}

	static function shift(m:{year:Int, month:Int}, n:Int):{year:Int, month:Int} {
		var total = m.year * 12 + m.month + n;
		return {year: Math.floor(total / 12), month: ((total % 12) + 12) % 12};
	}

	/** Adds months, clamping the day to the last day of the destination month. **/
	static function monthOver(d:CalendarDay, n:Int):CalendarDay {
		var m = shift({year: d.year, month: d.month}, n);
		var days = DateTools.getMonthDays(new Date(m.year, m.month, 1, 0, 0, 0));
		return {year: m.year, month: m.month, day: Std.int(Math.min(d.day, days))};
	}
}

/** A displayed month with entry and exit directions for its sliding transition. **/
private class Page {
	public final year:Int;
	public final month:Int;
	public final enter:Null<String>;
	public final leaving = Signal.make((null : Null<String>));
	public var element:Null<ashui.ui.Div> = null;

	public function new(year:Int, month:Int, enter:Null<String>) {
		this.year = year;
		this.month = month;
		this.enter = enter;
	}
}
