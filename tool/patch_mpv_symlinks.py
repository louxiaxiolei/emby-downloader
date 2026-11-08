#!/usr/bin/env python3
"""Fix media_kit's iOS framework symlink script before CocoaPods runs it.

media_kit_libs_ios_video 1.1.4 runs `cut -d '-' -f 1 -f 3`. macOS cut rejects
two -f lists, the script exits, and the podspec ignores that failure. The
linker then reports "Framework 'Mpv' not found". A warm pub-cache hides it
because old symlinks are reused; a lockfile change downloads a fresh copy
and the bug shows up.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

NEEDLE = "cut -d '-' -f 1 -f 3"
REPLACEMENT = "cut -d '-' -f 1,3"


def main() -> int:
    root = Path.home() / ".pub-cache" / "hosted" / "pub.dev"
    scripts = sorted(root.glob("media_kit_libs_ios_video-*/ios/create_framework_symlinks.sh"))
    if not scripts:
        print("media_kit_libs_ios_video is not in the pub cache", file=sys.stderr)
        return 1
    for script in scripts:
        text = script.read_text()
        if NEEDLE in text:
            script.write_text(text.replace(NEEDLE, REPLACEMENT))
            print(f"patched {script}")
        elif REPLACEMENT in text:
            print(f"already patched {script}")
        else:
            print(f"unexpected symlink script {script}", file=sys.stderr)
            return 1
        symlinks = script.parent / "Frameworks" / ".symlinks"
        if symlinks.exists():
            shutil.rmtree(symlinks)
            print(f"removed {symlinks} so make recreates it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
