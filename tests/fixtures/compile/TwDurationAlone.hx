// expect: tw: duration-, ease- and delay- need a transition class, such as transition or transition-colors
class TwDurationAlone {
	static function main() {
		ashui.style.Tw.tw("duration-200 bg-surface");
	}
}
