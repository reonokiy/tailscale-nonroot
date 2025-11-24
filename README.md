# tailscale-nonroot

Install Tailscale in user space (no root required) with a userspace tun. The script fetches the latest release tag from GitHub by default.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/reonokiy/tailscale-nonroot/main/install.sh | bash
```

Install a specific version (example: `1.74.0`):

```bash
curl -fsSL https://raw.githubusercontent.com/reonokiy/tailscale-nonroot/main/install.sh | bash -s -- 1.74.0
```

Or set an environment variable:

```bash
TAILSCALE_VERSION=1.74.0 bash install.sh
```

## After install

- Parameterized wrappers live under `~/.tailscale/cmd/{tailscale,tailscaled}`. The installer links `~/.local/bin/tailscale` to the wrapper so it automatically talks to your user-space socket.
- The script installs and enables `tailscaled.service` as a systemd user service (userspace networking). If systemd user services aren’t available, it falls back to managing `tailscaled` with [PM2](https://pm2.keymetrics.io/) when `pm2` is present, or prints the command to run manually.

## Running without systemd

If your environment lacks systemd user services, install PM2 as your user (e.g., `npm install -g pm2`) **before** running the installer so the script can keep `tailscaled` alive via PM2. You can also configure PM2 auto-start with `pm2 startup`.

To start `tailscaled` manually, run the wrapper the installer created:

```bash
~/.tailscale/cmd/tailscaled
```
