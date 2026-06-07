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
HOST="${REMOTE#*@}"
VLESS_PORT="${VLESS_PORT:-443}"

ping_host() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      ping -n 2 "$HOST"
      ;;
    *)
      ping -c 2 "$HOST"
      ;;
  esac
}

echo "=== 1. Ping (ICMP) — не проверяет VPN ==="
ping_host 2>/dev/null || echo "(ping пропущен или недоступен)"

echo
echo "=== 2. TCP ${VLESS_PORT} с вашего ПК ==="
test_tcp_port() {
  # Git Bash: nc часто врёт (FAIL при рабочем VPN) — сначала PowerShell / bash tcp
  if command -v powershell.exe >/dev/null 2>&1; then
    if powershell.exe -NoProfile -Command \
      "(Test-NetConnection -ComputerName '$HOST' -Port $VLESS_PORT -WarningAction SilentlyContinue).TcpTestSucceeded" 2>/dev/null \
      | grep -qi true; then
      return 0
    fi
  fi
  if (echo >/dev/tcp/"$HOST"/"$VLESS_PORT") 2>/dev/null; then
    return 0
  fi
  if command -v nc >/dev/null 2>&1 && nc -z -w 5 "$HOST" "$VLESS_PORT" 2>/dev/null; then
    return 0
  fi
  if command -v nc >/dev/null 2>&1 && nc -zv -w 5 "$HOST" "$VLESS_PORT" 2>&1 | grep -qi succeeded; then
    return 0
  fi
  return 1
}

if test_tcp_port; then
  echo "OK: TCP ${VLESS_PORT} до ${HOST} доступен"
else
  echo "FAIL: TCP ${VLESS_PORT} недоступен с ПК (ISP/фаервол) — VPN не подключится"
  echo "      Проверка вручную: powershell -Command \"Test-NetConnection ${HOST} -Port ${VLESS_PORT}\""
fi

echo
echo "=== 3. Состояние на сервере ==="
ssh -o ConnectTimeout=10 "$REMOTE" bash -s <<EOF
set -e
cd $REMOTE_DIR
docker compose ps
echo "--- listen ${VLESS_PORT} ---"
ss -tlnp | grep ":${VLESS_PORT}" || true
echo "--- последние подключения (accepted) ---"
docker logs xray-vless 2>&1 | grep 'accepted tcp' | tail -5 || echo "(пока нет — включите VPN и повторите diagnose)"
echo "--- dest reach ---"
curl -sI --connect-timeout 3 https://duckduckgo.com | head -1
EOF

echo
echo "=== 4. Ссылка из .env ==="
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
  echo "vless://${VLESS_UUID}@${SERVER_HOST}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=${REALITY_FINGERPRINT:-firefox}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#${CLIENT_NAME}"
  echo
  echo "Клиент: security=reality | flow=xtls-rprx-vision | SNI=${REALITY_SERVER_NAME} | shortId=${REALITY_SHORT_ID} | fp=${REALITY_FINGERPRINT:-firefox}"
fi

echo
echo "=== Итог ==="
echo "Главный признак рабочего VPN: в блоке 3 есть свежие строки 'accepted tcp' с вашего IP."
echo "Если accepted есть, а браузер не открывается — смотрите DNS/маршруты в v2rayN (bypass IP сервера)."
echo "FAIL в п.2 при наличии accepted — часто ложный тест nc в Git Bash; доверяйте PowerShell или логам."
