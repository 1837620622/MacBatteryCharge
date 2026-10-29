#!/usr/bin/env python3
"""Produce a release ZIP containing signed shortcuts and local installer."""
from __future__ import annotations
import argparse
import hashlib
import pathlib
import shutil
import zipfile

FILES = {
    "安装.command": "scripts/install.command",
    "检查状态.command": "scripts/status.command",
    "立即校准.command": "scripts/sync_now.command",
    "卸载.command": "scripts/uninstall.command",
    "scripts/charge_sync.sh": "scripts/charge_sync.sh",
    "scripts/profile.sh": "scripts/profile.sh",
    "使用说明.md": "docs/INSTALL.md",
}
SHORTCUTS = ("白天充电上限80", "晚间充电上限100")


def package(repo: pathlib.Path, signed_dir: pathlib.Path, target: pathlib.Path) -> pathlib.Path:
    dist = target / "MacBatteryCharge"
    if dist.exists():
        shutil.rmtree(dist)
    dist.mkdir(parents=True)
    for relative, source in FILES.items():
        dst = dist / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / source, dst)
        if dst.suffix in (".command", ".sh"):
            dst.chmod(0o755)
    (dist / "shortcuts").mkdir()
    for name in SHORTCUTS:
        path = signed_dir / f"{name}.shortcut"
        if not path.is_file() or path.stat().st_size < 100:
            raise ValueError(f"Missing signed shortcut: {path}")
        header = path.read_bytes()[:4]
        if header != b"AEA1":
            raise ValueError(f"Not an Apple signed shortcut archive: {path}, header={header!r}")
        shutil.copy2(path, dist / "shortcuts" / path.name)
    manifest = []
    for path in sorted(p for p in dist.rglob("*") if p.is_file()):
        manifest.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(dist).as_posix()}")
    (dist / "SHA256SUMS.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    target.mkdir(parents=True, exist_ok=True)
    zip_path = target / "MacBatteryCharge-macOS-Installer.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in sorted(p for p in dist.rglob("*") if p.is_file()):
            rel = path.relative_to(target).as_posix()
            info = zipfile.ZipInfo(rel)
            info.create_system = 3
            info.external_attr = ((0o100755 if path.suffix in (".command", ".sh") else 0o100644) << 16)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, path.read_bytes())
    with zipfile.ZipFile(zip_path) as z:
        if z.testzip() is not None:
            raise RuntimeError("ZIP CRC check failed")
        for name in SHORTCUTS:
            assert f"MacBatteryCharge/shortcuts/{name}.shortcut" in z.namelist()
    print(f"Release ready: {zip_path}")
    return zip_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path("."))
    parser.add_argument("--signed", type=pathlib.Path, default=pathlib.Path("build/signed"))
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("dist"))
    args = parser.parse_args()
    package(args.repo, args.signed, args.out)

if __name__ == "__main__":
    main()
