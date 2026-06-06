#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
TEMPLATE="${ROOT_DIR}/config/config.json.template"
OUTPUT="${ROOT_DIR}/config/config.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env — run deploy.sh first or copy .env.example to .env" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

required=(
  VLESS_PORT VLESS_UUID
  REALITY_PRIVATE_KEY REALITY_SHORT_ID
  REALITY_SERVER_NAME REALITY_DEST
)

for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Empty required variable: $var" >&2
    exit 1
  fi
done

render_with_python() {
  local py=python3
  command -v python3 >/dev/null 2>&1 || py=python
  VLESS_PORT="$VLESS_PORT" \
  VLESS_UUID="$VLESS_UUID" \
  VLESS_CLIENTS="${VLESS_CLIENTS:-}" \
  REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY" \
  REALITY_SHORT_ID="$REALITY_SHORT_ID" \
  REALITY_SHORT_ID_LEGACY="${REALITY_SHORT_ID_LEGACY:-}" \
  REALITY_SERVER_NAME="$REALITY_SERVER_NAME" \
  REALITY_SERVER_NAMES="${REALITY_SERVER_NAMES:-}" \
  REALITY_DEST="$REALITY_DEST" \
  TEMPLATE="$TEMPLATE" \
  OUTPUT="$OUTPUT" \
  "$py" <<'PY'
import json
import os
import re

path = os.environ["TEMPLATE"]
out = os.environ["OUTPUT"]

def parse_clients(value, fallback_uuid):
    clients = []
    raw_items = [item.strip() for item in value.replace("\n", ",").split(",") if item.strip()]
    if not raw_items:
        raw_items = [fallback_uuid]
    for item in raw_items:
        parts = item.split(":", 1)
        uuid = parts[0].strip()
        email = parts[1].strip() if len(parts) == 2 and parts[1].strip() else None
        if not re.fullmatch(r"[0-9a-fA-F-]{36}", uuid):
            raise SystemExit(f"Invalid VLESS client UUID: {uuid}")
        client = {"id": uuid, "flow": "xtls-rprx-vision"}
        if email:
            client["email"] = email
        clients.append(client)
    return clients

def parse_server_names(value, fallback_name):
    names = [item.strip() for item in value.replace("\n", ",").split(",") if item.strip()]
    if fallback_name not in names:
        names.insert(0, fallback_name)
    return names

clients_json = json.dumps(
    parse_clients(os.environ.get("VLESS_CLIENTS", ""), os.environ["VLESS_UUID"]),
    ensure_ascii=False,
    indent=10,
)
server_names_json = json.dumps(
    parse_server_names(os.environ.get("REALITY_SERVER_NAMES", ""), os.environ["REALITY_SERVER_NAME"]),
    ensure_ascii=False,
)

replacements = {
    "VLESS_PORT": os.environ["VLESS_PORT"],
    "VLESS_UUID": os.environ["VLESS_UUID"],
    "VLESS_CLIENTS_JSON": clients_json,
    "REALITY_PRIVATE_KEY": os.environ["REALITY_PRIVATE_KEY"],
    "REALITY_SHORT_ID": os.environ["REALITY_SHORT_ID"],
    "REALITY_SHORT_ID_LEGACY": os.environ.get("REALITY_SHORT_ID_LEGACY", ""),
    "REALITY_SERVER_NAME": os.environ["REALITY_SERVER_NAME"],
    "REALITY_SERVER_NAMES_JSON": server_names_json,
    "REALITY_DEST": os.environ["REALITY_DEST"],
}

text = open(path, encoding="utf-8").read()
for key, value in replacements.items():
    text = text.replace("${" + key + "}", value)
open(out, "w", encoding="utf-8", newline="\n").write(text)
PY
}

if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  render_with_python
else
  echo "Need python for config render" >&2
  exit 1
fi

echo "Rendered $OUTPUT"
