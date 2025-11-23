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

- Wrapper script is placed at `~/.local/bin/tailscale`. Make sure `~/.local/bin` is in `PATH`.
- The script installs and enables `tailscaled.service` as a systemd user service (userspace networking). If systemd user services aren’t available in the current session, you can start it later with `systemctl --user enable --now tailscaled.service`.
