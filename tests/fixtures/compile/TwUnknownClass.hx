// expect: tw: unknown class bg-surfce; did you mean bg-surface?
class TwUnknownClass {
	static function main() {
		ashui.style.Tw.tw("p-4 bg-surfce");
	}
}
