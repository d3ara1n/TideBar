#!/usr/bin/env python3
"""为 CI 预热 Sparkle 二进制缓存；来源与校验值均来自锁定版本。"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote, urlsplit


REPOSITORY = "sparkle-project/Sparkle"
ROOT = Path(__file__).resolve().parents[1]


def api(endpoint, *, accept="application/vnd.github+json", output=subprocess.PIPE):
    return subprocess.run(
        ["gh", "api", "--header", f"Accept: {accept}", endpoint],
        stdout=output, check=True, timeout=120,
    ).stdout


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(cache_path):
    pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
    pin = next(pin for pin in pins if pin["identity"] == "sparkle")
    if pin["location"] != f"https://github.com/{REPOSITORY}":
        raise ValueError("Unexpected Sparkle repository in Package.resolved")
    revision = pin["state"]["revision"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Expected a locked Sparkle commit SHA")

    # 让 Swift 求值锁定提交的 manifest，不复制版本号、不手写依赖的校验值。
    with tempfile.TemporaryDirectory(prefix="tidebar-sparkle-manifest-") as directory:
        manifest = Path(directory) / "Package.swift"
        manifest.write_bytes(api(
            f"repos/{REPOSITORY}/contents/Package.swift?ref={revision}",
            accept="application/vnd.github.raw+json",
        ))
        package = json.loads(subprocess.run(
            ["swift", "package", "--package-path", directory, "dump-package"],
            stdout=subprocess.PIPE, check=True, timeout=120,
        ).stdout)
    target = next(target for target in package["targets"]
                  if target["name"] == "Sparkle" and target["type"] == "binary")
    expected = target["checksum"]
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Expected a SHA-256 checksum in Sparkle's manifest")
    url = target["url"]
    parsed = urlsplit(url)
    prefix = f"/{REPOSITORY}/releases/download/"
    if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(prefix):
        raise ValueError("Expected an official GitHub Sparkle release URL")
    tag, name = parsed.path[len(prefix):].split("/", 1)
    release = json.loads(api(f"repos/{REPOSITORY}/releases/tags/{quote(tag, safe='')}"))
    asset = next(asset for asset in release["assets"]
                 if asset["name"] == name and asset["browser_download_url"] == url)
    if asset.get("digest") not in (None, f"sha256:{expected}"):
        raise ValueError("Release asset digest differs from the locked manifest")

    # SwiftPM 的 artifact 缓存键是下载 URL 的 C99 标识符形式；不改 workspace-state
    # 或解压目录。SwiftPM 后续仍按原 manifest 再次校验并解压此归档。
    cache = cache_path / "artifacts" / re.sub(r"[^a-zA-Z0-9_]", "_", url)
    cache.parent.mkdir(parents=True, exist_ok=True)
    if cache.is_file() and checksum(cache) == expected:
        print(f"Verified cached Sparkle artifact: {pin['state']['version']}")
        return
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=cache.parent, prefix=".sparkle-", delete=False) as archive:
            temporary = Path(archive.name)
            api(f"repos/{REPOSITORY}/releases/assets/{asset['id']}",
                accept="application/octet-stream", output=archive)
        if checksum(temporary) != expected:
            raise ValueError("Downloaded Sparkle artifact failed SHA-256 verification")
        temporary.replace(cache)
        print(f"Prepared verified Sparkle artifact: {pin['state']['version']} ({expected})")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-path", required=True, type=Path,
                        help="CI job-local SwiftPM cache directory")
    prepare(parser.parse_args().cache_path.resolve())
