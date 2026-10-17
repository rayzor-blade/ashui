"""Release archive contracts; no native compilation or haxelib account needed."""

import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("package_haxelib", ROOT / "scripts/package_haxelib.py")
PACKAGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGER)


class PackageTest(unittest.TestCase):
    def test_release_versions(self):
        self.assertEqual(PACKAGER.version_of("v2026.10.07"), "2026.10.7")
        self.assertEqual(PACKAGER.version_of("0.1.0-rc.1"), "0.1.0-rc.1")
        for invalid in ("nightly", "v1.2", "1.2.3-other", "1.2.3-rc.01"):
            with self.assertRaises(ValueError):
                PACKAGER.version_of(invalid)

    def test_readme_links_and_embeds_become_absolute(self):
        source = "\n".join([
            "![Banner](docs/images/charts-dark.png)",
            '<img src="./docs/images/ashui-logo.png" width="200">',
            '<video src="docs/images/drawer-motion.gif" poster="docs/images/charts-light.png"></video>',
            "See [debugging](docs/debugging.md#the-inspector), the [license](LICENSE) and the [components](components).",
            "[ref]: canvaskit/README.md",
            "[site](https://ash.rayzor.tech/) and [top](#usage) stay as they are.",
            "```haxe",
            '<a href="docs/not-a-link">code is left as written</a> and [x](also/not/a/link)',
            "```",
            "Inline `[x](still/code)` too.",
        ])
        out = PACKAGER.rewrite_links(source, ROOT)
        raw, page = PACKAGER.README_IMAGE_BASE, PACKAGER.README_LINK_BASE
        self.assertIn(f"![Banner]({raw}docs/images/charts-dark.png)", out)
        self.assertIn(f'<img src="{raw}docs/images/ashui-logo.png" width="200">', out)
        self.assertIn(f'<video src="{raw}docs/images/drawer-motion.gif" poster="{raw}docs/images/charts-light.png">', out)
        self.assertIn(f"[debugging]({page}docs/debugging.md#the-inspector)", out)
        self.assertIn(f"[license]({page}LICENSE)", out)
        self.assertIn("[components](https://github.com/rayzor-blade/ashui/tree/main/components)", out)
        self.assertIn(f"[ref]: {page}canvaskit/README.md", out)
        self.assertIn("[site](https://ash.rayzor.tech/) and [top](#usage)", out)
        self.assertIn('<a href="docs/not-a-link">code is left as written</a> and [x](also/not/a/link)', out)
        self.assertIn("`[x](still/code)`", out)
        self.assertEqual(PACKAGER.relative_references(out), [])
        self.assertEqual(PACKAGER.relative_references(source),
                         ["docs/images/charts-dark.png", "docs/debugging.md#the-inspector", "LICENSE", "components",
                          "canvaskit/README.md", "./docs/images/ashui-logo.png", "docs/images/drawer-motion.gif",
                          "docs/images/charts-light.png"])
        with self.assertRaisesRegex(ValueError, "missing file"):
            PACKAGER.rewrite_links("[gone](docs/no-such-file.md)", ROOT)

    def test_missing_platform_prevents_partial_release(self):
        with tempfile.TemporaryDirectory() as directory:
            assets = Path(directory)
            with self.assertRaisesRegex(ValueError, "missing release HDLLs"):
                PACKAGER.package(assets)
            self.assertEqual(list(assets.iterdir()), [])

    def test_archives_include_native_installer_css_and_matching_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            assets = Path(directory)
            platforms = json.loads((ROOT / "native/hdlls.json").read_text())
            for platform, entry in platforms.items():
                (assets / entry["releaseAsset"]).write_bytes(platform.encode())
            with self.assertRaisesRegex(ValueError, "missing release tools"):
                PACKAGER.package(assets, check=True)
            for platform, entry in platforms.items():
                for name, tool in entry.get("tools", {}).items():
                    (assets / tool["releaseAsset"]).write_bytes(f"{name} {platform}".encode())
            PACKAGER.package(assets, check=True)
            self.assertEqual(list(assets.glob("*.zip")), [])
            outputs = PACKAGER.package(assets, "2026.10.7")
            self.assertEqual({path.stem for path in outputs},
                             {"ashui", "ashui-components", "ashui-canvaskit", "ashui-media", "ashui-icons"})
            for path in outputs:
                with ZipFile(path) as archive:
                    lib = json.loads(archive.read("haxelib.json"))
                    self.assertEqual(lib["version"], "2026.10.7")
                    self.assertEqual(lib["license"], "Apache")
                    packaged_readme = archive.read("README.md").decode()
                    self.assertRegex(packaged_readme, rf"(?m)^# {re.escape(path.stem)}$")
                    source_root = ROOT if path.stem == "ashui" else ROOT / path.stem.removeprefix("ashui-")
                    source_readme = (source_root / "README.md").read_text()
                    images = re.findall(r"!\[[^\n]*?\]\(([^)]+)\)", source_readme)
                    self.assertTrue(images, f"{path.stem} has no showcase images")
                    for image in images:
                        self.assertFalse(image.startswith("https:"), "repository image should resolve locally")
                        source = (source_root / image).resolve()
                        self.assertTrue(source.is_file(), f"missing local image: {source}")
                        published = "https://raw.githubusercontent.com/rayzor-blade/ashui/main/" + source.relative_to(ROOT).as_posix()
                        self.assertIn(f"]({published})", packaged_readme)
                        self.assertNotIn(f"]({image})", packaged_readme)
                    for image in re.findall(r"<img\b[^>]*?\bsrc\s*=\s*[\"']([^\"']+)[\"']", source_readme,
                                            flags=re.IGNORECASE):
                        source = (source_root / image).resolve()
                        self.assertTrue(source.is_file(), f"missing local image: {source}")
                        published = PACKAGER.README_IMAGE_BASE + source.relative_to(ROOT).as_posix()
                        self.assertIn(f'src="{published}"', packaged_readme)
                        self.assertNotIn(f'src="{image}"', packaged_readme)
                    # Haxelib's page cannot follow a path into the repository: nothing relative may be left.
                    self.assertEqual(PACKAGER.relative_references(packaged_readme), [])
                    self.assertIn("Apache License", archive.read("LICENSE").decode())
                    self.assertFalse(any(name.startswith(("tools/", "tests/", "target/"))
                                         for name in archive.namelist()))
                    for dependency, version in lib["dependencies"].items():
                        if dependency == "ashui" or dependency.startswith("ashui-"):
                            self.assertEqual(version, "2026.10.7")
                    if path.stem == "ashui":
                        self.assertIn("ashui.ui.Markup.enable()", archive.read("extraParams.hxml").decode())
                        self.assertIn("haxe/ashui/macro/NativeInstall.hx", archive.namelist())
                        # The fonts a web build carries, with the licence they are under.
                        self.assertIn("ashui.macro.DefaultFonts.stage()", archive.read("extraParams.hxml").decode())
                        for font in ("Arimo.woff2", "Arimo-Italic.woff2", "OFL.txt"):
                            self.assertIn(f"fonts/{font}", archive.namelist())
                        self.assertIn("wasm32-wasip1-threads", platforms)
                        for platform, entry in platforms.items():
                            self.assertEqual(archive.read(entry["packagePath"]), platform.encode())
                            if platform == "wasm32-wasip1-threads":
                                continue  # The page's library has no build tools.
                            self.assertIn("blinc-css", entry["tools"])
                            for name, tool in entry["tools"].items():
                                self.assertEqual(archive.read(tool["packagePath"]), f"{name} {platform}".encode())
                                mode = archive.getinfo(tool["packagePath"]).external_attr >> 16
                                self.assertTrue(mode & 0o111, f"{tool['packagePath']} is not executable")
                    elif path.stem == "ashui-icons":
                        # The catalogue, its icons and the licence they are under.
                        for member in ("haxe/ashui/icons/Remix.hx", "haxe/ashui/icons/remix/LICENSE", "haxe/ashui/icons/remix/Media/play-line.svg"):
                            self.assertIn(member, archive.namelist())
                        self.assertGreater(len([n for n in archive.namelist() if n.endswith(".svg")]), 3000)
                    elif path.stem in ("ashui-components", "ashui-media"):
                        name = path.stem.removeprefix("ashui-")
                        self.assertIn(f"css/{name}.css", archive.namelist())
                        self.assertIn(f"haxe/ashui/{name}/Library.hx", archive.namelist())


if __name__ == "__main__":
    unittest.main()
