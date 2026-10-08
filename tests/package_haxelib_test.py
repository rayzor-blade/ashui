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
            PACKAGER.package(assets, check=True)
            self.assertEqual(list(assets.glob("*.zip")), [])
            outputs = PACKAGER.package(assets, "2026.10.7")
            self.assertEqual({path.stem for path in outputs},
                             {"ashui", "ashui-components", "ashui-canvaskit", "ashui-media"})
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
                    self.assertIn("Apache License", archive.read("LICENSE").decode())
                    self.assertFalse(any(name.startswith(("tools/", "tests/", "target/"))
                                         for name in archive.namelist()))
                    for dependency, version in lib["dependencies"].items():
                        if dependency == "ashui" or dependency.startswith("ashui-"):
                            self.assertEqual(version, "2026.10.7")
                    if path.stem == "ashui":
                        self.assertIn("ashui.ui.Markup.enable()", archive.read("extraParams.hxml").decode())
                        self.assertIn("haxe/ashui/macro/NativeInstall.hx", archive.namelist())
                        for platform, entry in platforms.items():
                            self.assertEqual(archive.read(entry["packagePath"]), platform.encode())
                    elif path.stem in ("ashui-components", "ashui-media"):
                        name = path.stem.removeprefix("ashui-")
                        self.assertIn(f"css/{name}.css", archive.namelist())
                        self.assertIn(f"haxe/ashui/{name}/Library.hx", archive.namelist())


if __name__ == "__main__":
    unittest.main()
