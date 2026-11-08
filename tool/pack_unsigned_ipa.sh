#!/usr/bin/env bash
# Pack a Flutter --no-codesign Runner.app into an unsigned IPA.
# The archive is a zip whose root is Payload/Runner.app, with no
# embedded.mobileprovision and no code signature.
set -euo pipefail

APP_PATH="${1:-build/ios/iphoneos/Runner.app}"
OUT_PATH="${2:-artifacts/emby-downloader-unsigned.ipa}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "找不到 $APP_PATH。先运行 flutter build ios --release --no-codesign" >&2
  exit 1
fi

CODESIGN_LOG="$(mktemp)"
if codesign -d "$APP_PATH" >"$CODESIGN_LOG" 2>&1; then
  echo "Runner.app 已经有签名。--no-codesign 应产出未签名应用，拒绝打包。" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi
if ! grep -q "not signed" "$CODESIGN_LOG"; then
  echo "codesign 的结果不是“未签名”，停止打包。" >&2
  cat "$CODESIGN_LOG" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/Runner.app"
find "$STAGE/Payload" -name '*.mobileprovision' -delete
find "$STAGE/Payload" -name '_CodeSignature' -type d -prune -exec rm -rf {} +
# Drop local symbols so the unsigned IPA stays smaller. This does not sign the app.
if command -v strip >/dev/null 2>&1; then
  while IFS= read -r -d '' bin; do
    strip -x -S "$bin" 2>/dev/null || true
  done < <(find "$STAGE/Payload/Runner.app" -type f -print0)
fi

OUT_ABS="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$OUT_PATH")"
mkdir -p "$(dirname "$OUT_ABS")"
rm -f "$OUT_ABS"
(
  cd "$STAGE"
  zip -qry "$OUT_ABS" Payload
)

unzip -l "$OUT_ABS" | grep -q "Payload/Runner.app/Info.plist"
echo "未签名 IPA：$OUT_ABS"
