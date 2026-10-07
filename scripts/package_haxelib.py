#!/usr/bin/env python3
"""Package ashui and its optional libraries from prebuilt release HDLLs."""

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent.parent
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(alpha|beta|rc)(\.(0|[1-9]\d*))?)?")
PACKAGES = (ROOT, ROOT / "components", ROOT / "canvaskit", ROOT / "media")
README_IMAGE_BASE = "https://raw.githubusercontent.com/rayzor-blade/ashui/main/"


def release_readme(readme: Path) -> str:
    """Keep repository previews local; use published images on Haxelib."""
    def image_url(match: re.Match) -> str:
        source = (readme.parent / match[2]).resolve()
        if not source.is_file():
            raise ValueError(f"missing README image: {source}")
        relative = source.relative_to(ROOT).as_posix()
        return match[1] + README_IMAGE_BASE + relative + match[3]

    return re.sub(r"(!\[[^\n]*?\]\()((?:\.\./)?docs/images/[^)\s]+)(\))",
                  image_url, readme.read_text())


def version_of(tag: str) -> str:
    """Normalize release tags such as v2026.10.07 to Haxelib's 2026.10.7."""
    core, _, preview = tag.removeprefix("v").partition("-")
    if not re.fullmatch(r"\d+\.\d+\.\d+", core):
        raise ValueError(f"{tag} is not a Haxelib version")
    version = ".".join(str(int(part)) for part in core.split("."))
    if preview:
        version += "-" + preview
    if not SEMVER.fullmatch(version):
        raise ValueError(f"{tag} is not a Haxelib version")
    return version


def package(assets: Path, version: str | None = None, check: bool = False) -> list[Path]:
    platforms = json.loads((ROOT / "native/hdlls.json").read_text())
    missing = [entry["releaseAsset"] for entry in platforms.values()
               if not (assets / entry["releaseAsset"]).is_file()]
    if missing:
        raise ValueError("missing release HDLLs: " + ", ".join(missing))
    if check:
        return []

    outputs = []
    for source_root in PACKAGES:
        lib = json.loads((source_root / "haxelib.json").read_text())
        if version:
            lib["version"] = version
            # Side libraries use the core and controls from the same release.
            for dependency in lib["dependencies"]:
                if dependency == "ashui" or dependency.startswith("ashui-"):
                    lib["dependencies"][dependency] = version
        output = assets / f"{lib['name']}.zip"
        with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
            archive.writestr("haxelib.json", json.dumps(lib, indent=2) + "\n")
            archive.write(ROOT / "LICENSE", "LICENSE")
            readme = source_root / "README.md"
            archive.writestr("README.md", release_readme(readme if readme.is_file() else ROOT / "README.md"))
            for directory in (lib["classPath"], "css"):
                for source in sorted((source_root / directory).rglob("*")):
                    if source.is_file():
                        archive.write(source, source.relative_to(source_root))
            if source_root == ROOT:
                for name in ("extraParams.hxml", "native/hdlls.json"):
                    archive.write(ROOT / name, name)
                for entry in platforms.values():
                    archive.write(assets / entry["releaseAsset"], entry["packagePath"])
        outputs.append(output)
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="directory holding every native/hdlls.json releaseAsset")
    parser.add_argument("--check", action="store_true", help="only check that every native asset exists")
    parser.add_argument("--version", help="release tag to stamp into every package")
    args = parser.parse_args()
    try:
        version = version_of(args.version) if args.version else None
        for output in package(args.assets, version, args.check):
            print(f"wrote {output}")
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
