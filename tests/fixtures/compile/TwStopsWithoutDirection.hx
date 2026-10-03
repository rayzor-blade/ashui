// expect: tw: from-, via- and to- need a direction, such as bg-linear-to-r or bg-radial
class TwStopsWithoutDirection {
	static function main() {
		ashui.style.Tw.tw("from-primary to-accent");
	}
}
