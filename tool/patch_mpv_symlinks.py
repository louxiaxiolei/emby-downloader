#!/usr/bin/env python3
"""Fix media_kit's iOS framework symlink script before CocoaPods runs it.

media_kit_libs_ios_video 1.1.4 runs `cut -d '-' -f 1 -f 3`. macOS cut rejects
two -f lists, the script exits, and the podspec ignores that failure. The
linker then reports "Framework 'Mpv' not found". A warm pub-cache hides it
because old symlinks are reused; a lockfile change downloads a fresh copy
and the bug shows up.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

NEEDLE = "cut -d '-' -f 1 -f 3"
REPLACEMENT = "cut -d '-' -f 1,3"
IOS_ASSET = "https://api.github.com/repos/media-kit/libmpv-darwin-build/releases/assets/127491793"
ANDROID_ASSETS = {
    "default-arm64-v8a.jar": "300465119",
    "default-armeabi-v7a.jar": "300465118",
    "default-x86_64.jar": "300465116",
    "default-x86.jar": "300465120",
}
DOWNLOAD_RECIPE = r"""	i=1; while [ $$i -le 4 ]; do \
		curl -fL --retry 3 --retry-delay 2 \
			-H "Accept: application/octet-stream" \
			-H "User-Agent: emby-downloader" \
			"__ASSET__" \
			-o .cache/xcframeworks/libmpv.tar.gz.tmp \
		&& shasum -a 256 -c <<< '${MPV_XCFRAMEWORKS_SHA256SUM}  .cache/xcframeworks/libmpv.tar.gz.tmp' \
		&& break; \
		echo "libmpv download failed, retry $$i"; \
		rm -f .cache/xcframeworks/libmpv.tar.gz.tmp; \
		i=$$((i+1)); sleep 3; \
	done
	test -s .cache/xcframeworks/libmpv.tar.gz.tmp
"""


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
        makefile = script.parent / "Makefile"
        make_text = makefile.read_text()
        if IOS_ASSET in make_text:
            print(f"ios download already uses the GitHub API {makefile}")
        else:
            patched_make, count = re.subn(
                r"\tcurl .*?libmpv\.tar\.gz\.tmp\n\tshasum .*?libmpv\.tar\.gz\.tmp'\n",
                DOWNLOAD_RECIPE.replace("__ASSET__", IOS_ASSET),
                make_text,
                count=1,
                flags=re.S,
            )
            if count != 1:
                print(f"could not find the libmpv curl recipe in {makefile}", file=sys.stderr)
                return 1
            makefile.write_text(patched_make)
            print(f"patched {makefile}")
        symlinks = script.parent / "Frameworks" / ".symlinks"
        if symlinks.exists():
            shutil.rmtree(symlinks)
            print(f"removed {symlinks} so make recreates it")
    gradle_files = sorted(root.glob("media_kit_libs_android_video-*/android/build.gradle"))
    if not gradle_files:
        print("media_kit_libs_android_video is not in the pub cache", file=sys.stderr)
        return 1
    old_download = """destFile.withOutputStream { os ->
                    os << new URL(fileInfo.url).openStream()
                }"""
    new_download = """destFile.withOutputStream { os ->
                    def connection = new URL(fileInfo.url).openConnection()
                    connection.setRequestProperty("Accept", "application/octet-stream")
                    connection.setRequestProperty("User-Agent", "emby-downloader")
                    connection.setConnectTimeout(30000)
                    connection.setReadTimeout(180000)
                    connection.inputStream.withCloseable { input -> os << input }
                }"""
    vendored = """def vendored = new File(rootProject.projectDir, "../third_party/libmpv/${destFile.name}")
            if (!destFile.exists() && vendored.exists()) {
                destFile.parentFile.mkdirs()
                java.nio.file.Files.copy(vendored.toPath(), destFile.toPath())
                println "Using vendored ${vendored}"
            }
            """
    for gradle in gradle_files:
        text = gradle.read_text()
        original = text
        for name, asset_id in ANDROID_ASSETS.items():
            api = f"https://api.github.com/repos/media-kit/libmpv-android-video-build/releases/assets/{asset_id}"
            release = f"https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/{name}"
            if release in text:
                text = text.replace(release, api)
        if old_download in text:
            text = text.replace(old_download, new_download)
        if "third_party/libmpv" not in text and "if (!destFile.exists())" in text:
            text = text.replace("if (!destFile.exists())", vendored + "if (!destFile.exists())", 1)
        kept = []
        for line in text.splitlines(keepends=True):
            if "default-x86" in line:
                continue
            kept.append(line)
        text = "".join(kept)
        if "default-arm64-v8a.jar" not in text or "third_party/libmpv" not in text:
            print(f"unexpected android download script {gradle}", file=sys.stderr)
            return 1
        if text != original:
            gradle.write_text(text)
            print(f"patched {gradle}")
        else:
            print(f"android download already vendored {gradle}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
