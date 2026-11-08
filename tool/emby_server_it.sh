#!/usr/bin/env bash
# Start the official Emby Server, add one generated movie, and run the clip test.
set -euo pipefail

if docker info >/dev/null 2>&1; then
  docker_cmd=(docker)
elif sudo docker info >/dev/null 2>&1; then
  docker_cmd=(sudo docker)
else
  echo "docker is required" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffmpeg and ffprobe are required" >&2
  exit 1
fi

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
  "${docker_cmd[@]}" rm -f emby-it >/dev/null 2>&1 || true
  chmod -R u+w "$work" 2>/dev/null || true
  rm -rf "$work" 2>/dev/null || sudo rm -rf "$work" || true
}
trap cleanup EXIT

mkdir -p "$work/media" "$work/config"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=size=160x120:rate=25" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t 40 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  "$work/media/clip.mkv"
chmod -R a+rX "$work/media"

"${docker_cmd[@]}" rm -f emby-it >/dev/null 2>&1 || true
"${docker_cmd[@]}" run -d --name emby-it -p 8096:8096 \
  -v "$work/config:/config" \
  -v "$work/media:/media" \
  emby/embyserver:4.8.11.0

base=http://127.0.0.1:8096/emby
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "$base/System/Info/Public"; then
    break
  fi
  sleep 1
done
curl -fsS -o /dev/null "$base/System/Info/Public"

curl -fsS -o /dev/null -X POST "$base/Startup/Configuration" \
  -H 'Content-Type: application/json' \
  -d '{"UICulture":"en-us","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
curl -fsS -o /dev/null -X POST "$base/Startup/User" \
  -H 'Content-Type: application/json' \
  -d '{"Name":"clip","Password":"clip-pass-1"}'
curl -fsS -o /dev/null -X POST "$base/Startup/Complete"

auth='Emby Client="emby-it", Device="ci", DeviceId="ci-device", Version="1.0.0"'
curl -fsS -o "$work/auth.json" -X POST "$base/Users/AuthenticateByName" \
  -H 'Content-Type: application/json' \
  -H "X-Emby-Authorization: $auth" \
  -d '{"Username":"clip","Pw":"clip-pass-1"}'
token=$(python3 -c 'import json; print(json.load(open("'"$work/auth.json"'"))["AccessToken"])')
user=$(python3 -c 'import json; print(json.load(open("'"$work/auth.json"'"))["User"]["Id"])')

curl -fsS -o /dev/null -X POST "$base/Library/VirtualFolders" \
  -H "X-Emby-Token: $token" -H 'Content-Type: application/json' \
  -d '{"Name":"Clips","CollectionType":"homevideos","Paths":["/media"],"RefreshLibrary":true}'

# The library watcher imports a file about 90s after the last change.
# Copy after the watcher is up so the event is not missed.
sleep 3
"${docker_cmd[@]}" cp "$work/media/clip.mkv" emby-it:/media/clip.mkv

python3 - "$base" "$token" "$user" "$work/item.json" <<'PY'
import json, sys, time, urllib.request
base, token, user, dest = sys.argv[1:]
deadline = time.time() + 150
found = None
while time.time() < deadline:
    req = urllib.request.Request(
        f"{base}/Users/{user}/Items?Recursive=true&IncludeItemTypes=Video&Fields=MediaSources,Path",
        headers={"X-Emby-Token": token},
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        payload = json.load(response)
    for item in payload.get("Items") or []:
        if str(item.get("Path") or "").endswith("clip.mkv"):
            source = (item.get("MediaSources") or [{}])[0]
            found = {
                "apiRoot": base,
                "accessToken": token,
                "itemId": item["Id"],
                "mediaSourceId": source.get("Id") or "",
                "container": source.get("Container") or "mkv",
            }
            break
    if found:
        break
    time.sleep(3)
if not found:
    raise SystemExit("Emby did not import clip.mkv")
with open(dest, "w", encoding="utf-8") as handle:
    json.dump(found, handle)
print("imported", found["itemId"], found["mediaSourceId"], found["container"])
PY

export EMBY_IT_JSON="$work/item.json"
cd "$root"
flutter test test/emby_server_test.dart --reporter compact
