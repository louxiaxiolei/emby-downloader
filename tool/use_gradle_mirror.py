#!/usr/bin/env python3
"""Point the Gradle wrapper at a mirror when GitHub releases return 504.

services.gradle.org redirects to github.com/gradle/gradle-distributions.
That redirect has been failing in GitHub Actions. The wrapper file in git
keeps the official URL; this script is only run by CI after the check fails.
"""

from pathlib import Path

PATH = Path("android/gradle/wrapper/gradle-wrapper.properties")
OLD = "https\\://services.gradle.org/distributions/gradle-8.12-all.zip"
NEW = "https\\://repo.huaweicloud.com/gradle/gradle-8.12-all.zip"


def main() -> None:
    text = PATH.read_text()
    if OLD not in text:
        raise SystemExit(f"gradle wrapper URL not found in {PATH}")
    PATH.write_text(text.replace(OLD, NEW, 1))
    print(f"gradle distribution set to {NEW}")


if __name__ == "__main__":
    main()
