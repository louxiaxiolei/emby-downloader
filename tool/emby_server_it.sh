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

# Info/Public answers before the wizard will accept configuration.
post_ok() {
  local url="$1"
  local data="$2"
  local code body
  body=$(mktemp)
  for _ in $(seq 1 30); do
    code=$(curl -sS -o "$body" -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' -d "$data" || echo 000)
    if [ "$code" = 200 ] || [ "$code" = 204 ]; then
      rm -f "$body"
      return 0
    fi
    sleep 2
  done
  echo "POST $url failed HTTP $code" >&2
  cat "$body" >&2 || true
  rm -f "$body"
  return 1
}
post_ok "$base/Startup/Configuration" '{"UICulture":"en-us","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
post_ok "$base/Startup/User" '{"Name":"clip","Password":"clip-pass-1"}'
complete_code=000
complete_body=$(mktemp)
for _ in $(seq 1 30); do
  complete_code=$(curl -sS -o "$complete_body" -w '%{http_code}' -X POST "$base/Startup/Complete" || echo 000)
  if [ "$complete_code" = 200 ] || [ "$complete_code" = 204 ]; then
    break
  fi
  sleep 2
done
if [ "$complete_code" != 200 ] && [ "$complete_code" != 204 ]; then
  echo "POST $base/Startup/Complete failed HTTP $complete_code" >&2
  cat "$complete_body" >&2 || true
  exit 1
fi
rm -f "$complete_body"

auth='Emby Client="emby-it", Device="ci", DeviceId="ci-device", Version="1.0.0"'
auth_code=000
for _ in $(seq 1 15); do
  auth_code=$(curl -sS -o "$work/auth.json" -w '%{http_code}' -X POST "$base/Users/AuthenticateByName" \
    -H 'Content-Type: application/json' \
    -H "X-Emby-Authorization: $auth" \
    -d '{"Username":"clip","Pw":"clip-pass-1"}' || echo 000)
  if [ "$auth_code" = 200 ]; then
    break
  fi
  sleep 2
done
if [ "$auth_code" != 200 ]; then
  echo "AuthenticateByName failed HTTP $auth_code" >&2
  cat "$work/auth.json" >&2 || true
  echo >&2
  curl -sS "$base/Users/Public" >&2 || true
  exit 1
fi
token=$(python3 -c 'import json; print(json.load(open("'"$work/auth.json"'"))["AccessToken"])')
user=$(python3 -c 'import json; print(json.load(open("'"$work/auth.json"'"))["User"]["Id"])')

curl -fsS -o /dev/null -X POST "$base/Library/VirtualFolders" \
  -H "X-Emby-Token: $token" -H 'Content-Type: application/json' \
  -d '{"Name":"Clips","CollectionType":"homevideos","Paths":["/media"],"RefreshLibrary":true}'

# The library watcher imports a file about 90s after the last change.
# Copy after the watcher is up so the event is not missed.
sleep 3
"${docker_cmd[@]}" cp "$work/media/clip.mkv" emby-it:/media/clip.mkv

curl -fsS -o "$work/user2.json" -X POST "$base/Users/New" \
  -H "X-Emby-Token: $token" -H 'Content-Type: application/json' \
  -d '{"Name":"clip2"}'
user2=$(python3 -c 'import json; print(json.load(open("'"$work/user2.json"'"))["Id"])')
curl -fsS -o /dev/null -X POST "$base/Users/$user2/Password" \
  -H "X-Emby-Token: $token" -H 'Content-Type: application/json' \
  -d '{"Id":"'"$user2"'","NewPw":"clip-pass-2"}'
curl -fsS -o "$work/auth2.json" -X POST "$base/Users/AuthenticateByName" \
  -H 'Content-Type: application/json' \
  -H "X-Emby-Authorization: $auth" \
  -d '{"Username":"clip2","Pw":"clip-pass-2"}'

python3 - "$base" "$token" "$user" "$work/item.json" "$work/auth2.json" <<'PY'
import json, sys, time, urllib.request
base, token, user, dest, auth2_path = sys.argv[1:]
auth2 = json.load(open(auth2_path))
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
                "accessToken2": auth2["AccessToken"],
                "userId2": auth2["User"]["Id"],
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
