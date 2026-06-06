#!/usr/bin/env bash
set -euo pipefail

REMOTE="${REMOTE:-root@93.123.13.8}"
REMOTE_DIR="${REMOTE_DIR:-/opt/vless-vpn}"
HOST="${REMOTE#*@}"

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
echo "=== 2. TCP 443 с вашего ПК ==="
test_tcp_443() {
  # Git Bash: nc часто врёт (FAIL при рабочем VPN) — сначала PowerShell / bash tcp
  if command -v powershell.exe >/dev/null 2>&1; then
    if powershell.exe -NoProfile -Command \
      "(Test-NetConnection -ComputerName '$HOST' -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded" 2>/dev/null \
      | grep -qi true; then
      return 0
    fi
  fi
  if (echo >/dev/tcp/"$HOST"/443) 2>/dev/null; then
    return 0
  fi
  if command -v nc >/dev/null 2>&1 && nc -z -w 5 "$HOST" 443 2>/dev/null; then
    return 0
  fi
  if command -v nc >/dev/null 2>&1 && nc -zv -w 5 "$HOST" 443 2>&1 | grep -qi succeeded; then
    return 0
  fi
  return 1
}

if test_tcp_443; then
  echo "OK: TCP 443 до ${HOST} доступен"
else
  echo "FAIL: TCP 443 недоступен с ПК (ISP/фаервол) — VPN не подключится"
  echo "      Проверка вручную: powershell -Command \"Test-NetConnection ${HOST} -Port 443\""
fi

echo
echo "=== 3. Состояние на сервере ==="
ssh -o ConnectTimeout=10 "$REMOTE" bash -s <<EOF
set -e
cd $REMOTE_DIR
docker compose ps
echo "--- listen 443 ---"
ss -tlnp | grep ':443' || true
echo "--- последние подключения (accepted) ---"
docker logs xray-vless 2>&1 | grep 'accepted tcp' | tail -5 || echo "(пока нет — включите VPN и повторите diagnose)"
echo "--- dest reach ---"
curl -sI --connect-timeout 3 https://www.google.com | head -1
EOF

echo
echo "=== 4. Ссылка из .env ==="
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
