// expect: ICON_SET_DIRECTORY: cannot find
@:build(ashui.svg.IconSet.build(["icons-that-do-not-exist"]))
class Icons {}

class IconSetMissing {
	static function main() {}
}
