# Happ / FlyFrog Notes

If Happ logs show a direct TCP connection to the VPN server and then a forced close, the TUN route is probably catching the VPN server address itself.

Typical symptom:

```text
inbound/tun -> YOUR_SERVER_IP:443
outbound/direct -> YOUR_SERVER_IP:443
ERROR: forcibly closed by the remote host
```

Fix in Happ:

1. Reimport the fresh `vless://` link printed by `deploy.sh` or `scripts/add-user.sh`.
2. Add the server IP to TUN bypass / route exclusions.
3. Check that the profile uses Reality, `xtls-rprx-vision`, SNI from `.env`, and shortId from `.env`.

Generated client JSON files are ignored by Git because they contain live connection details.
