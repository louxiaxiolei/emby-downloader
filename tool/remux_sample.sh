#!/usr/bin/env bash
# Build a short MKV with ffmpeg and remux it to MP4 without re-encoding.
# This is the recipe the app asks libmpv to follow when a recording is not
# already a Photos-friendly mp4/mov. HEVC, when the encoder exists, must
# land with the hvc1 tag.
set -euo pipefail

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffmpeg and ffprobe are required" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=size=160x120:rate=25" \
  -f lavfi -i "sine=frequency=1000:sample_rate=48000" \
  -t 1 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  -f matroska "$work/sample.mkv"

ffmpeg -hide_banner -loglevel error -y \
  -i "$work/sample.mkv" -c copy -movflags +faststart \
  "$work/sample.mp4"

duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/sample.mp4")
vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$work/sample.mp4")
acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$work/sample.mp4")
format=$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$work/sample.mp4")

python3 - "$duration" "$vcodec" "$acodec" "$format" <<'PY'
import sys
duration, vcodec, acodec, format_name = sys.argv[1:]
if float(duration) < 0.5:
    raise SystemExit(f"remux duration too small: {duration}")
if vcodec != "h264":
    raise SystemExit(f"expected h264, got {vcodec}")
if acodec != "aac":
    raise SystemExit(f"expected aac, got {acodec}")
if "mp4" not in format_name:
    raise SystemExit(f"expected mp4 container, got {format_name}")
print(f"h264 remux ok duration={duration} format={format_name}")
PY

if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265; then
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc=size=160x120:rate=25" \
    -t 1 -c:v libx265 -tag:v hvc1 -an \
    -f matroska "$work/hevc.mkv"
  ffmpeg -hide_banner -loglevel error -y \
    -i "$work/hevc.mkv" -c copy -tag:v hvc1 \
    "$work/hevc.mp4"
  tag=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_tag_string -of csv=p=0 "$work/hevc.mp4")
  codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$work/hevc.mp4")
  if [[ "$codec" != "hevc" || "$tag" != "hvc1" ]]; then
    echo "expected hevc/hvc1, got $codec/$tag" >&2
    exit 1
  fi
  echo "hevc remux ok tag=$tag"
else
  echo "libx265 is not installed; skipped the hvc1 tag check"
fi
