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

render_with_envsubst() {
  export VLESS_PORT VLESS_UUID REALITY_PRIVATE_KEY REALITY_SHORT_ID
  export REALITY_SHORT_ID_LEGACY="${REALITY_SHORT_ID_LEGACY:-}"
  export REALITY_SERVER_NAME REALITY_DEST
  envsubst '${VLESS_PORT} ${VLESS_UUID} ${REALITY_PRIVATE_KEY} ${REALITY_SHORT_ID} ${REALITY_SHORT_ID_LEGACY} ${REALITY_SERVER_NAME} ${REALITY_DEST}' \
    < "$TEMPLATE" > "$OUTPUT"
}

render_with_python() {
  local py=python3
  command -v python3 >/dev/null 2>&1 || py=python
  VLESS_PORT="$VLESS_PORT" \
  VLESS_UUID="$VLESS_UUID" \
  REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY" \
  REALITY_SHORT_ID="$REALITY_SHORT_ID" \
  REALITY_SERVER_NAME="$REALITY_SERVER_NAME" \
  REALITY_DEST="$REALITY_DEST" \
  TEMPLATE="$TEMPLATE" \
  OUTPUT="$OUTPUT" \
  "$py" <<'PY'
import os
from string import Template

path = os.environ["TEMPLATE"]
out = os.environ["OUTPUT"]
keys = (
    "VLESS_PORT", "VLESS_UUID", "REALITY_PRIVATE_KEY", "REALITY_SHORT_ID",
    "REALITY_SHORT_ID_LEGACY", "REALITY_SERVER_NAME", "REALITY_DEST",
)
text = open(path, encoding="utf-8").read()
for key in keys:
    text = text.replace("${" + key + "}", os.environ[key])
open(out, "w", encoding="utf-8", newline="\n").write(text)
PY
}

if command -v envsubst >/dev/null 2>&1; then
  render_with_envsubst
elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  render_with_python
else
  echo "Need envsubst (gettext) or python for config render" >&2
  exit 1
fi

echo "Rendered $OUTPUT"
