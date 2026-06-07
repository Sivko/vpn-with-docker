#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi
SERVER_HOST="${SERVER_HOST:-YOUR_SERVER_IP_OR_DOMAIN}"
REMOTE="${REMOTE:-root@${SERVER_HOST}}"
REMOTE_DIR="${REMOTE_DIR:-/opt/vless-vpn}"
VLESS_PORT="${VLESS_PORT:-443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-duckduckgo.com}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-firefox}"

usage() {
  cat <<EOF
Usage: $0 USER_NAME

Examples:
  $0 user-06
  REMOTE=root@YOUR_SERVER_IP_OR_DOMAIN $0 alice
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

USER_NAME="${1:-}"
if [[ -z "$USER_NAME" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "$USER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid USER_NAME. Use only letters, digits, dot, underscore, and dash." >&2
  exit 1
fi

ssh -o ConnectTimeout=10 "$REMOTE" \
  "REMOTE_DIR='$REMOTE_DIR' USER_NAME='$USER_NAME' SERVER_HOST='$SERVER_HOST' VLESS_PORT='$VLESS_PORT' REALITY_SERVER_NAME='$REALITY_SERVER_NAME' REALITY_PUBLIC_KEY='$REALITY_PUBLIC_KEY' REALITY_SHORT_ID='$REALITY_SHORT_ID' REALITY_FINGERPRINT='$REALITY_FINGERPRINT' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

cd "$REMOTE_DIR"

NEW_UUID="$(cat /proc/sys/kernel/random/uuid)"

NEW_UUID="$NEW_UUID" USER_NAME="$USER_NAME" python3 - <<'PY'
import os
from pathlib import Path

env_path = Path(".env")
text = env_path.read_text(encoding="utf-8")
new_client = f"{os.environ['NEW_UUID']}:{os.environ['USER_NAME']}"

lines = text.splitlines()
for index, line in enumerate(lines):
    if line.startswith("VLESS_CLIENTS="):
        value = line.split("=", 1)[1].strip()
        clients = [item.strip() for item in value.split(",") if item.strip()]
        names = {item.split(":", 1)[1] for item in clients if ":" in item}
        if os.environ["USER_NAME"] in names:
            raise SystemExit(f"User already exists: {os.environ['USER_NAME']}")
        clients.append(new_client)
        lines[index] = "VLESS_CLIENTS=" + ",".join(clients)
        break
else:
    lines.append("VLESS_CLIENTS=" + new_client)

env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

bash scripts/render-config.sh
docker run --rm \
  -v "$REMOTE_DIR/config/config.json:/etc/xray/config.json:ro" \
  teddysun/xray:latest xray -test -config /etc/xray/config.json >/dev/null
docker compose restart xray >/dev/null

printf '%s: vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp#%s\n' \
  "$USER_NAME" "$NEW_UUID" "$SERVER_HOST" "$VLESS_PORT" "$REALITY_SERVER_NAME" "$REALITY_FINGERPRINT" "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$USER_NAME"
REMOTE_SCRIPT

scp -q "$REMOTE:$REMOTE_DIR/.env" "$ROOT_DIR/.env" \
  || echo "Warning: user created, but failed to sync remote .env back to $ROOT_DIR/.env" >&2
