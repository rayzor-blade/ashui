// expect: tw: a variant needs a class for the same property without one
class TwVariantWithoutBase {
	static function main() {
		ashui.style.Tw.tw("p-4 hover:bg-primary");
	}
}
