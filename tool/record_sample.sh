#!/usr/bin/env bash
# Play a generated MKV over HTTP with mpv and check two recording methods.
#
# stream-record, set after the demuxer cache is already full and cleared
# before another packet is read, matches the empty file seen on device.
# dump-cache must write that already-played range to a playable file.
set -euo pipefail

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1 || ! command -v mpv >/dev/null 2>&1; then
  echo "ffmpeg, ffprobe, and mpv are required" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'if [[ -n "${server_pid:-}" ]]; then kill "$server_pid" 2>/dev/null || true; fi; rm -rf "$work"' EXIT

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=size=160x120:rate=25" \
  -f lavfi -i "sine=frequency=1000:sample_rate=48000" \
  -t 16 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest \
  -f matroska "$work/sample.mkv"

python3 -m http.server 8765 --bind 127.0.0.1 --directory "$work" >/tmp/record-sample-http.log 2>&1 &
server_pid=$!
ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS -o /dev/null "http://127.0.0.1:8765/sample.mkv" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.2
done
if [[ "$ready" != 1 ]]; then
  echo "sample HTTP server did not start" >&2
  exit 1
fi

python3 - "$work" <<'PY'
import json, os, socket, subprocess, sys, time

work = sys.argv[1]
sock_path = os.path.join(work, "mpv.sock")
url = "http://127.0.0.1:8765/sample.mkv"
stream_path = os.path.join(work, "stream-record.mkv")
dump_path = os.path.join(work, "dump-cache.mkv")
for path in (sock_path, stream_path, dump_path):
    if os.path.exists(path):
        os.remove(path)

proc = subprocess.Popen(
    [
        "mpv",
        "--idle=yes",
        "--no-terminal",
        "--force-window=no",
        "--vo=null",
        "--ao=null",
        "--pause=yes",
        "--cache=yes",
        "--demuxer-max-bytes=32MiB",
        "--demuxer-readahead-secs=20",
        "--demuxer-max-back-bytes=300MiB",
        "--demuxer-seekable-cache=yes",
        f"--input-ipc-server={sock_path}",
    ],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
)
try:
    deadline = time.time() + 5
    while not os.path.exists(sock_path):
        if time.time() > deadline:
            err = proc.stderr.read().decode("utf-8", "replace") if proc.stderr else ""
            raise SystemExit(f"mpv ipc socket was not created\n{err}")
        time.sleep(0.05)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(sock_path)
    sock.settimeout(5)
    next_id = 1

    def command(args):
        global next_id
        request_id = next_id
        next_id += 1
        payload = json.dumps({"command": args, "request_id": request_id}) + "\n"
        sock.sendall(payload.encode())
        buf = b""
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                msg = json.loads(line)
                if msg.get("request_id") == request_id:
                    return msg
        raise SystemExit(f"no ipc reply for {args}")

    load = command(["loadfile", url, "replace"])
    if load.get("error") != "success":
        raise SystemExit(f"loadfile failed: {load}")
    command(["set_property", "pause", False])

    def wait_pos(target):
        for _ in range(80):
            reply = command(["get_property", "time-pos"])
            data = reply.get("data")
            if isinstance(data, (int, float)) and data >= target:
                return data
            time.sleep(0.25)
        raise SystemExit(f"playback did not reach {target}s")

    wait_pos(4)
    # Cache is already ahead of the playhead. Clear the recorder before the
    # demuxer has to read another packet.
    command(["set_property", "stream-record", stream_path])
    time.sleep(0.3)
    command(["set_property", "stream-record", ""])
    time.sleep(0.3)
    stream_size = os.path.getsize(stream_path) if os.path.exists(stream_path) else 0
    print(f"stream-record size={stream_size} path={stream_path}")

    wait_pos(8)
    dumped = command(["dump-cache", "1", "7", dump_path])
    print(f"dump-cache reply={dumped.get('error')}")
    time.sleep(0.4)
    dump_size = os.path.getsize(dump_path) if os.path.exists(dump_path) else 0
    print(f"dump-cache size={dump_size} path={dump_path}")
    if dumped.get("error") != "success" or dump_size < 1024:
        raise SystemExit("dump-cache did not write a playable clip")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()

print("dump-cache file is non-empty")
PY

ffprobe -v error -show_entries format=duration:stream=codec_name -of default=nw=1 "$work/dump-cache.mkv"
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/dump-cache.mkv")
python3 - "$duration" <<'PY'
import sys
duration = float(sys.argv[1])
if duration < 1:
    raise SystemExit(f"dump-cache duration too small: {duration}")
print(f"dump-cache playable duration={duration}")
PY
