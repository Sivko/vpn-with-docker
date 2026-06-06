#!/usr/bin/env bash
set -euo pipefail

# Деплой VLESS (Xray + Reality) на Ubuntu-сервер
# Использование: ./deploy.sh
# Требуется: ssh-доступ к root@93.123.13.8 (ключ в ssh-agent)

REMOTE_USER="root"
REMOTE_HOST="93.123.13.8"
REMOTE="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_DIR="/opt/vless-vpn"

LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${LOCAL_DIR}/.env"

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Команда '$1' не найдена. Установите её и повторите."
}

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
    return
  fi
  if command -v python >/dev/null 2>&1; then
    python -c 'import uuid; print(uuid.uuid4())'
    return
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm teddysun/xray:latest cat /proc/sys/kernel/random/uuid
    return
  fi
  # Git Bash / Windows: openssl (уже обязателен для deploy.sh)
  local b variant
  b="$(openssl rand -hex 16)"
  variant="$(printf '%02x' $((0x${b:16:2} & 0x3f | 0x80)))"
  printf '%s-%s-4%s-%s%s-%s\n' \
    "${b:0:8}" "${b:8:4}" "${b:12:3}" "${variant}" "${b:18:2}" "${b:20:12}"
}

generate_short_id() {
  # 4 байта (8 hex) — совместимость с v2rayN / Nekoray / Hiddify
  openssl rand -hex 4
}

generate_reality_keys() {
  local output private public
  output="$(docker run --rm teddysun/xray:latest xray x25519)"
  private="$(echo "$output" | grep -i PrivateKey | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  public="$(echo "$output" | grep -iE 'PublicKey|Password' | head -1 | awk -F': ' '{print $2}' | tr -d '[:space:]')"
  if [[ -z "$private" || -z "$public" ]]; then
    die "Не удалось сгенерировать Reality-ключи. Запустите Docker локально."
  fi
  printf '%s\n%s\n' "$private" "$public"
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    log "Создаю .env из .env.example"
    cp "${LOCAL_DIR}/.env.example" "$ENV_FILE"
  fi

  # shellcheck disable=SC1090
  source "$ENV_FILE"

  local changed=0

  if [[ -z "${VLESS_UUID:-}" ]]; then
    VLESS_UUID="$(generate_uuid)"
    changed=1
    log "Сгенерирован VLESS_UUID"
  fi

  if [[ -z "${REALITY_PRIVATE_KEY:-}" || -z "${REALITY_PUBLIC_KEY:-}" ]]; then
    log "Генерирую Reality-ключи (нужен локальный Docker)..."
    mapfile -t keys < <(generate_reality_keys)
    REALITY_PRIVATE_KEY="${keys[0]}"
    REALITY_PUBLIC_KEY="${keys[1]}"
    changed=1
  fi

  if [[ -z "${REALITY_SHORT_ID:-}" ]]; then
    REALITY_SHORT_ID="$(generate_short_id)"
    changed=1
    log "Сгенерирован REALITY_SHORT_ID"
  fi

  : "${SERVER_HOST:=${REMOTE_HOST}}"
  : "${VLESS_PORT:=443}"
  : "${REALITY_SERVER_NAME:=www.google.com}"
  : "${REALITY_DEST:=www.google.com:443}"
  : "${REALITY_FINGERPRINT:=firefox}"
  : "${REALITY_SHORT_ID_LEGACY:=}"
  : "${CLIENT_NAME:=vpn-server}"

  if [[ "$changed" -eq 1 ]]; then
    cat > "$ENV_FILE" <<EOF
SERVER_HOST=${SERVER_HOST}
VLESS_PORT=${VLESS_PORT}
VLESS_UUID=${VLESS_UUID}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}
REALITY_SHORT_ID=${REALITY_SHORT_ID}
REALITY_SHORT_ID_LEGACY=${REALITY_SHORT_ID_LEGACY}
REALITY_SERVER_NAME=${REALITY_SERVER_NAME}
REALITY_DEST=${REALITY_DEST}
REALITY_FINGERPRINT=${REALITY_FINGERPRINT}
CLIENT_NAME=${CLIENT_NAME}
EOF
    log "Обновлён $ENV_FILE"
  fi
}

print_client_link() {
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  local encoded_name
  encoded_name="$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CLIENT_NAME}'))" 2>/dev/null \
    || printf '%s' "${CLIENT_NAME}" | sed 's/ /%20/g')"

  local link
  link="vless://${VLESS_UUID}@${SERVER_HOST}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=${REALITY_FINGERPRINT:-firefox}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#${encoded_name}"

  echo
  echo "========== Клиентская ссылка VLESS =========="
  echo "$link"
  echo "============================================="
  echo
  echo "Параметры для ручной настройки:"
  echo "  Address:  ${SERVER_HOST}"
  echo "  Port:     ${VLESS_PORT}"
  echo "  UUID:     ${VLESS_UUID}"
  echo "  Flow:     xtls-rprx-vision"
  echo "  Security: reality"
  echo "  SNI:      ${REALITY_SERVER_NAME}"
  echo "  Public:   ${REALITY_PUBLIC_KEY}"
  echo "  Short ID: ${REALITY_SHORT_ID}"
  echo
}

main() {
  need_cmd ssh
  need_cmd scp
  need_cmd openssl

  log "Проверка SSH до ${REMOTE}..."
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" "echo ok" >/dev/null \
    || die "Нет SSH-доступа к ${REMOTE}. Добавьте ключ: ssh-copy-id ${REMOTE}"

  if ! command -v docker >/dev/null 2>&1; then
    die "Локальный Docker нужен для генерации Reality-ключей (один раз)."
  fi

  ensure_env

  log "Рендер config.json..."
  bash "${LOCAL_DIR}/scripts/render-config.sh"

  log "Копирование файлов на сервер..."
  ssh "$REMOTE" "mkdir -p ${REMOTE_DIR}/config ${REMOTE_DIR}/scripts"
  scp -q "${LOCAL_DIR}/docker-compose.yml" "${REMOTE}:${REMOTE_DIR}/"
  scp -q "${LOCAL_DIR}/config/config.json" "${REMOTE}:${REMOTE_DIR}/config/"
  scp -q "${LOCAL_DIR}/.env" "${REMOTE}:${REMOTE_DIR}/.env"

  log "Установка Docker и запуск на сервере..."
  ssh "$REMOTE" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail
REMOTE_DIR="/opt/vless-vpn"
cd "$REMOTE_DIR"

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  echo "[remote] Установка Docker..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
}

install_docker

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 443/tcp comment 'vless-xray' || true
fi

docker compose pull
docker compose up -d
docker compose ps

echo "[remote] Xray запущен"
REMOTE_SCRIPT

  print_client_link
  log "Готово. Сервер: ${REMOTE}"
}

main "$@"
