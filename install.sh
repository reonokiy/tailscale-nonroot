#!/usr/bin/env bash
set -euo pipefail

# Figure out script dir if available (e.g. local exec); fall back to empty when piped
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "-" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tailscale-install.XXXXXX")"

log() {
  echo "[tailscale install] $*"
}

fail() {
  log "$*" >&2
  exit 1
}

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_cmd curl
require_cmd tar
require_cmd install

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    TAILSCALE_ARCH="amd64"
    ;;
  aarch64|arm64)
    TAILSCALE_ARCH="arm64"
    ;;
  armv7l|armv7|armv6l|armv6)
    TAILSCALE_ARCH="arm"
    ;;
  *)
    fail "Unsupported architecture: $ARCH. Download manually from https://pkgs.tailscale.com/"
    ;;
esac

TAILSCALE_HOME="$HOME/.tailscale"
BIN_DIR="$TAILSCALE_HOME/bin"
CMD_DIR="$TAILSCALE_HOME/cmd"
DATA_DIR="$TAILSCALE_HOME/data"
SOCKET_PATH="$TAILSCALE_HOME/tailscaled.sock"

fetch_latest_version() {
  local payload version
  payload=$(curl -fsSL https://api.github.com/repos/tailscale/tailscale/releases/latest 2>/dev/null || true)
  if [[ -n "$payload" ]]; then
    version=$(echo "$payload" | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)
    echo "$version"
  fi
}

VERSION="${1:-${TAILSCALE_VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(fetch_latest_version || true)"
  if [[ -z "$VERSION" ]]; then
    fail "Could not detect the latest version from GitHub. Pass a version as the first argument or set TAILSCALE_VERSION."
  fi
fi

log "Installing Tailscale ${VERSION} for ${TAILSCALE_ARCH}"

TARBALL_URL="https://pkgs.tailscale.com/stable/tailscale_${VERSION}_${TAILSCALE_ARCH}.tgz"
TARBALL_PATH="${TMP_DIR}/tailscale.tgz"
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"

if ! curl -fsSL "$TARBALL_URL" -o "$TARBALL_PATH"; then
  fail "Failed to download ${TARBALL_URL}. Pass an explicit version if this version is unavailable."
fi
tar -xzf "$TARBALL_PATH" -C "$EXTRACT_DIR" --strip-components=1

if [[ ! -x "$EXTRACT_DIR/tailscale" || ! -x "$EXTRACT_DIR/tailscaled" ]]; then
  fail "Downloaded archive is missing expected binaries."
fi

install -d "$BIN_DIR"
install -m 755 "$EXTRACT_DIR/tailscale" "$BIN_DIR/tailscale"
install -m 755 "$EXTRACT_DIR/tailscaled" "$BIN_DIR/tailscaled"
log "Tailscale binaries installed to $BIN_DIR"

install -d "$CMD_DIR"
install -d "$DATA_DIR"

cat > "${TMP_DIR}/tailscale-cmd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$HOME/.tailscale/bin/tailscale" --socket="$HOME/.tailscale/tailscaled.sock" "$@"
EOF
install -m 755 "${TMP_DIR}/tailscale-cmd" "$CMD_DIR/tailscale"

cat > "${TMP_DIR}/tailscaled-cmd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$HOME/.tailscale/bin/tailscaled" --statedir="$HOME/.tailscale/data" --socket="$HOME/.tailscale/tailscaled.sock" --tun=userspace-networking --port=41641 "$@"
EOF
install -m 755 "${TMP_DIR}/tailscaled-cmd" "$CMD_DIR/tailscaled"

log "Tailscale command wrappers installed to $CMD_DIR"

install -d "$HOME/.local/bin"
ln -sf "$CMD_DIR/tailscale" "$HOME/.local/bin/tailscale"
log "Tailscale command linked to $HOME/.local/bin/tailscale"

if [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]]; then
  log "Note: add $HOME/.local/bin to PATH to use the tailscale command without a full path."
fi

setup_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not found; skipping systemd --user service setup."
    return 1
  fi

  if ! systemctl --user show-environment >/dev/null 2>&1; then
    log "systemd user services are not available in this session; skipped tailscaled.service."
    return 1
  fi

  install -d "$HOME/.tailscale"
  install -d "$HOME/.config/systemd/user"
  local managed_service="$HOME/.tailscale/tailscaled.service"
  local service_path="$HOME/.config/systemd/user/tailscaled.service"

  if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/tailscaled.service" ]]; then
    cp "${SCRIPT_DIR}/tailscaled.service" "$managed_service"
  else
    log "Local tailscaled.service not found; downloading the service unit."
    if ! curl -fsSL https://raw.githubusercontent.com/reonokiy/tailscale-nonroot/main/tailscaled.service -o "$managed_service"; then
      log "Warning: failed to retrieve tailscaled.service; skipping systemd setup."
      return 1
    fi
  fi

  ln -sf "$managed_service" "$service_path"

  systemctl --user daemon-reload
  if systemctl --user enable tailscaled.service --now; then
    log "tailscaled.service installed and enabled."
  else
    log "tailscaled.service installed but enable/start failed. Try: systemctl --user enable --now tailscaled.service"
  fi

  return 0
}

setup_pm2_service() {
  if ! command -v pm2 >/dev/null 2>&1; then
    log "pm2 not found; install pm2 (e.g., 'npm install -g pm2') to manage tailscaled without systemd."
    return 1
  fi

  install -d "$TAILSCALE_HOME"
  install -d "$DATA_DIR"

  local tailscaled_cmd="$CMD_DIR/tailscaled"
  local pm2_name="tailscaled"

  if [[ ! -x "$tailscaled_cmd" ]]; then
    log "Expected wrapper $tailscaled_cmd not found or not executable."
    return 1
  fi

  pm2 delete "$pm2_name" >/dev/null 2>&1 || true
  if pm2 start "$tailscaled_cmd" --name "$pm2_name"; then
    pm2 save >/dev/null 2>&1 || true
    log "tailscaled is now managed by pm2 (process name: $pm2_name)."
    log "Run 'pm2 restart tailscaled' to restart it or 'pm2 startup' to auto-start on login."
    return 0
  fi

  log "pm2 failed to start tailscaled."
  return 1
}

setup_service() {
  if setup_systemd_service; then
    return
  fi

  log "Falling back to pm2 for tailscaled management."
  if setup_pm2_service; then
    return
  fi

  log "Automatic service setup was skipped. Start tailscaled manually with:"
  log "  $CMD_DIR/tailscaled"
}

setup_service
