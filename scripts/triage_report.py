#!/usr/bin/env python3
"""Unpack a Jamf Dash problem report and make it readable.

    scripts/triage_report.py JamfDash-JD-ABC123.zip [--dsyms Versions/JamfDash_v1.0/dSYMs]

Writes a folder next to the zip with:
  timeline.txt   log lines and jamf-cli commands merged by time
  crash-*.txt    each crash report with the app's frames resolved to function names
                 (needs the dSYMs of the version that crashed; release.sh keeps them in
                 Versions/JamfDash_v<version>/dSYMs)
and prints the report summary.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def find_dsyms(version: str | None, given: str | None) -> pathlib.Path | None:
    if given:
        return pathlib.Path(given)
    if version:
        for candidate in sorted((ROOT / "Versions").glob(f"JamfDash_v{version}*/dSYMs")):
            return candidate
    return None


def merge_timeline(folder: pathlib.Path) -> str:
    lines = []
    log = folder / "logs" / "jamfdash.log"
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", line)
            if m:
                lines.append((m.group(1)[11:], "LOG", line[len(m.group(1)):].strip()))
    cmds = folder / "cli-commands.txt"
    if cmds.exists():
        for line in cmds.read_text().splitlines():
            m = re.match(r"(\d\d:\d\d:\d\d)\S*\s+(.*)", line)
            if m:
                lines.append((m.group(1), "CLI", m.group(2)))
    lines.sort(key=lambda t: t[0])
    return "\n".join(f"{t}  {kind:3}  {text}" for t, kind, text in lines) + "\n"


def symbolicate(ips: pathlib.Path, dsyms: pathlib.Path | None) -> str:
    raw = ips.read_text(errors="replace")
    header, _, body = raw.partition("\n")
    try:
        meta, report = json.loads(header), json.loads(body)
    except json.JSONDecodeError:
        return raw
    images = report.get("usedImages", [])
    out = [f"{meta.get('app_name', '?')} {meta.get('app_version', '?')} ({meta.get('build_version', '?')}) "
           f"on {meta.get('os_version', '?')}",
           f"Exception: {json.dumps(report.get('exception', {}))}",
           f"Termination: {json.dumps(report.get('termination', {}))}", ""]
    for i, thread in enumerate(report.get("threads", [])):
        flag = "  (crashed)" if thread.get("triggered") else ""
        out.append(f"Thread {i}{flag} {thread.get('name', '')}")
        for n, frame in enumerate(thread.get("frames", [])):
            image = images[frame["imageIndex"]] if frame.get("imageIndex", -1) < len(images) else {}
            name = image.get("name", "?")
            symbol = frame.get("symbol")
            if not symbol and dsyms and name in ("JamfDash", "JamfDashCLIWorker"):
                binary = next(dsyms.glob(f"{name}*.dSYM/Contents/Resources/DWARF/*"), None)
                if binary:
                    load = image.get("base", 0)
                    addr = load + frame.get("imageOffset", 0)
                    symbol = subprocess.run(
                        ["atos", "-o", str(binary), "-l", hex(load), hex(addr)],
                        capture_output=True, text=True).stdout.strip()
            out.append(f"  {n:3} {name:28} {symbol or hex(frame.get('imageOffset', 0))}")
        out.append("")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip")
    parser.add_argument("--dsyms", help="dSYMs folder of the version that crashed")
    args = parser.parse_args()

    source = pathlib.Path(args.zip)
    dest = source.with_suffix("")
    with zipfile.ZipFile(source) as z:
        z.extractall(dest.parent)
    folder = dest if dest.is_dir() else next(dest.parent.glob("JamfDash-JD-*"))

    report = (folder / "report.md").read_text()
    version = re.search(r"Jamf Dash (\S+) \(build", report)
    print(report)

    (folder / "timeline.txt").write_text(merge_timeline(folder))
    print(f"Timeline: {folder / 'timeline.txt'}")

    dsyms = find_dsyms(version.group(1) if version else None, args.dsyms)
    for ips in sorted((folder / "crashes").glob("*")) if (folder / "crashes").exists() else []:
        target = folder / f"crash-{ips.stem}.txt"
        target.write_text(symbolicate(ips, dsyms))
        print(f"Crash:    {target}{'' if dsyms else '  (no dSYMs found: frames not resolved)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
