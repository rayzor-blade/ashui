#!/usr/bin/env python3
"""Package ashui and its optional libraries from prebuilt release HDLLs."""

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parent.parent
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(alpha|beta|rc)(\.(0|[1-9]\d*))?)?")
PACKAGES = (ROOT, ROOT / "components", ROOT / "canvaskit", ROOT / "media")
README_IMAGE_BASE = "https://raw.githubusercontent.com/rayzor-blade/ashui/main/"
README_LINK_BASE = "https://github.com/rayzor-blade/ashui/blob/main/"
# Files a README shows inline: served raw, so Haxelib's page can display them.
EMBEDDED = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".mp4", ".webm", ".mov")
# A target that already resolves anywhere: a scheme such as https: or mailto:, a protocol-relative URL, or a fragment.
ABSOLUTE = re.compile(r"(?i)^(?:[a-z][a-z0-9+.-]*:|//|#)")
# Where a README names a file: inline Markdown links and images, reference definitions, and HTML src, href and poster.
REFERENCES = (
    re.compile(r"(\]\()(<?)([^)\s>]+)(>?(?:\s+\"[^\"]*\")?\))"),
    re.compile(r"(?m)(^[ \t]{0,3}\[[^\]\n]+\]:[ \t]*<?)([^\s>]+)(>?)"),
    re.compile(r"(?i)(\b(?:src|href|poster)\s*=\s*[\"'])([^\"']+)([\"'])"),
)
# Fenced code blocks and inline code spans: their text is code, not links, and is left as written.
CODE = re.compile(r"(?ms)^(```|~~~).*?^\1[^\n]*$|`[^`\n]+`")


def outside_code(text: str, change) -> str:
    """`text` with `change` applied to everything but its code blocks and spans."""
    out, at = [], 0
    for code in CODE.finditer(text):
        out.append(change(text[at:code.start()]))
        out.append(code.group(0))
        at = code.end()
    out.append(change(text[at:]))
    return "".join(out)


def relative_references(text: str) -> list[str]:
    """Every file a README names by a relative path, outside code: what Haxelib's page cannot resolve."""
    found = []

    def collect(part: str) -> str:
        for pattern in REFERENCES:
            for match in pattern.finditer(part):
                target = match.group(match.lastindex - 1)
                if not ABSOLUTE.match(target):
                    found.append(target)
        return part

    outside_code(text, collect)
    return found


def rewrite_links(text: str, base: Path) -> str:
    """
    `text`, a README in `base`, with every relative link and embed pointing at the repository's main branch:
    images and video served raw so they display, other files at their page on GitHub. Each must name a file or
    folder in the repository; a fragment is kept. Raises if a target is missing or anything relative is left.
    """
    def published(target: str) -> str:
        path, mark, fragment = target.partition("#")
        source = (base / path).resolve()
        if not source.exists():
            raise ValueError(f"README links to a missing file: {source}")
        relative = source.relative_to(ROOT).as_posix()
        if source.suffix.lower() in EMBEDDED:
            return README_IMAGE_BASE + relative + mark + fragment
        page = README_LINK_BASE if source.is_file() else README_LINK_BASE.replace("/blob/", "/tree/")
        return page + relative + mark + fragment

    def change(part: str) -> str:
        for pattern in REFERENCES:
            def replace(match: re.Match) -> str:
                target = match.group(match.lastindex - 1)
                if ABSOLUTE.match(target):
                    return match.group(0)
                groups = list(match.groups())
                groups[match.lastindex - 2] = published(target)
                return "".join(groups)
            part = pattern.sub(replace, part)
        return part

    rewritten = outside_code(text, change)
    left = relative_references(rewritten)
    if left:
        raise ValueError("README links still relative after rewriting: " + ", ".join(left))
    return rewritten


def release_readme(readme: Path) -> str:
    """Keep repository previews local; on Haxelib, point every link and embed at the repository."""
    return rewrite_links(readme.read_text(), readme.parent)


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
    missing = [tool["releaseAsset"] for entry in platforms.values() for tool in entry.get("tools", {}).values()
               if not (assets / tool["releaseAsset"]).is_file()]
    if missing:
        raise ValueError("missing release tools: " + ", ".join(missing))
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
                    # The build tools macros run, executable once unpacked.
                    for tool in entry.get("tools", {}).values():
                        info = ZipInfo(tool["packagePath"], date_time=(1980, 1, 1, 0, 0, 0))
                        info.external_attr = 0o755 << 16
                        info.compress_type = ZIP_DEFLATED
                        archive.writestr(info, (assets / tool["releaseAsset"]).read_bytes())
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
