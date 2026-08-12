#!/usr/bin/env bash
set -euo pipefail

# Build locally, upload through Lazarus, install on the attached Flipper, and
# verify that the on-device file matches the local FAP.

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${LAZARUS_HOST:-madmin@10.0.0.171}"
port="${FLIPPER_PORT:-/dev/cu.usbmodemflip_Amuser1}"
remote_tmp="${LAZARUS_TMP_FAP:-/Users/madmin/meshtastic-latest.fap}"
flipper_path="${FLIPPER_APP_PATH:-/ext/apps/Tools/meshtastic.fap}"

cd "$repo"
python3 -m ufbt

local_fap="$repo/dist/meshtastic.fap"
local_md5="$(md5 -q "$local_fap")"

scp "$local_fap" "$host:$remote_tmp"

ssh "$host" \
    "FLIPPER_PORT='$port' REMOTE_TMP='$remote_tmp' FLIPPER_APP_PATH='$flipper_path' LOCAL_MD5='$local_md5' bash -s" <<'REMOTE'
set -euo pipefail
cd "$HOME/flipper-mcp"
. .venv/bin/activate

python - <<'PY'
import hashlib
import os
from pathlib import Path

from flipper_mcp.flipper import FlipperCli
from flipperzero_protobuf import FlipperProto

port = os.environ["FLIPPER_PORT"]
remote_tmp = Path(os.environ["REMOTE_TMP"])
flipper_path = os.environ["FLIPPER_APP_PATH"]
expected = os.environ["LOCAL_MD5"]
data = remote_tmp.read_bytes()

fp = FlipperProto(serial_port=port, debug=0)
try:
    try:
        fp.rpc_app_exit()
    except Exception as exc:
        print(f"app_exit warning: {exc}")
    fp.rpc_write(flipper_path, data)
    actual = fp.rpc_md5sum(flipper_path)
finally:
    try:
        fp.stop_rpc_session()
    except Exception:
        pass

print(f"wrote {len(data)} bytes to {flipper_path}")
print(f"local_md5={expected}")
print(f"remote_md5={actual}")
if actual != expected:
    raise SystemExit("md5 mismatch")

try:
    print(FlipperCli(port).command(f"loader open {flipper_path}", timeout=5.0))
except Exception as exc:
    print(f"loader open warning: {exc}")
PY
REMOTE
