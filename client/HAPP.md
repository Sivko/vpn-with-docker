# Happ (FlyFrog) — типичная ошибка

## Симптом в логах

```
inbound/tun → 23.164.240.80:443
outbound/direct → 23.164.240.80:443
ERROR: forcibly closed by the remote host (~19s)
```

Трафик к **IP VPN-сервера** попадает в TUN и уходит как **обычный TCP** (`direct`), без VLESS+Reality. Xray на сервере ждёт handshake Reality и закрывает соединение.

Сервер при этом исправен (в логах xray бывают `accepted tcp:...` с вашего IP).

## Что сделать в Happ

1. Удалите профиль и импортируйте ссылку заново.
2. Найдите настройки маршрутизации / TUN / «Исключения»:
   - добавьте **`23.164.240.80`** в исключения из VPN (bypass / route exclude);
   - или отключите «проксировать адрес сервера через туннель».
3. Режим: **глобальный VPN** или **правила**, но IP сервера не должен идти в tun как `direct` TCP.
4. Проверьте в профиле: **Reality**, flow **xtls-rprx-vision**, SNI **www.google.com**, shortId **8be758e2**.

## Альтернатива (проверено проще)

**v2rayN** или **Hiddify** — импорт той же `vless://` ссылки из deploy.

## Ручной конфиг sing-box

Файл `sing-box-happ.json` — импорт в Happ, если поддерживается JSON (с `route_exclude_address` для IP сервера).
