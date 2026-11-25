"""Copy named App Store and purchase screenshots out of an xcresult."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-Hans", "zh-Hant")
NAME = re.compile(r"^(store-(?:zh-Hans|zh-Hant|en)-\d{2}-[a-z][a-z0-9-]*|paid-01-paywall)(?=[_.]|$)")


def available_shots(folder):
    shots = {}
    manifest = folder / "manifest.json"
    if manifest.is_file():
        for test in json.loads(manifest.read_text(encoding="utf-8")):
            for attachment in test.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                match = NAME.match(name)
                source = folder / attachment["exportedFileName"]
                if match and source.is_file() and source.suffix.lower() == ".png":
                    shots[match[1]] = source
    for source in sorted(folder.rglob("*.png")):
        match = NAME.match(source.name)
        if match:
            shots.setdefault(match[1], source)
    return shots


def configured_shots(root):
    config = root / "上架资料" / "商店截图.json"
    if not config.is_file():
        return set()
    pages = json.loads(config.read_text(encoding="utf-8"))["pages"]
    return {"paid-01-paywall"} | {f"store-{lang}-{page['shot']}" for page in pages for lang in LANGUAGES}


def export(folder, output, required):
    shots = available_shots(folder)
    if not shots:
        raise ValueError("没有找到命名的界面测试截图")
    missing = sorted(required - shots.keys())
    if missing:
        raise ValueError("缺少截图：" + ", ".join(missing))
    output.mkdir(parents=True, exist_ok=True)
    for name, source in sorted(shots.items()):
        target = output / (name + ".png")
        if source.resolve() != target.resolve():
            shutil.copy2(source, target)
    return len(shots)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as temporary:
        folder = Path(temporary)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path",
                        str(args.xcresult), "--output-path", str(folder)], check=True)
        print(f"已导出 {export(folder, args.output, configured_shots(ROOT))} 张截图")


if __name__ == "__main__":
    main()
