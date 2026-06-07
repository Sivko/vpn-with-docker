# VLESS Reality VPN

Small Xray + Reality deployment for an Ubuntu server.

## What To Change

Before deploying to a new server, copy the example env file:

```bash
cp .env.example .env
```

Edit `.env` and change:

```env
SERVER_HOST=YOUR_SERVER_IP_OR_DOMAIN
```

Use the server IP, or a domain that resolves to the server IP. If SSH should connect to a different address than the public VPN address, run deploy with `REMOTE_HOST`:

```bash
REMOTE_HOST=YOUR_SERVER_IP ./deploy.sh
```

## Deploy

Requirements:

- SSH access as `root` to the server
- `ssh`, `scp`, `openssl`, and Docker locally for first key generation
- Ubuntu server with outbound internet access

Run:

```bash
./deploy.sh
```

The deploy script will:

- generate missing UUID and Reality keys in `.env`;
- render `config/config.json`;
- copy files to `/opt/vless-vpn`;
- install Docker on the server if needed;
- start/restart Xray;
- print a VLESS link.

## Add Users

```bash
./scripts/add-user.sh alice
```

The script updates the remote `.env`, rerenders Xray config, restarts Xray, and prints a link for the new user.

## Diagnostics

```bash
./scripts/diagnose.sh
```

## GitHub Safety

Do not commit `.env`, `config/config.json`, or generated files under `client/*.json`. They contain live connection details. Keep `.env.example`, templates, scripts, and this README in Git.
