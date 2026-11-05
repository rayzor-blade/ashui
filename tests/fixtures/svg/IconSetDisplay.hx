import ashui.svg.SvgDocument;

@:build(ashui.svg.IconSet.build(["icons-a", "icons-bad"]))
private class DisplayIcons {}

class IconSetDisplay {
    static function main() {
        var icons:Array<SvgDocument> = [DisplayIcons.PLAY, DisplayIcons.PAUSE, DisplayIcons.BAD];
    }
}
