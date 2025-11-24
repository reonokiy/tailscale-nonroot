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

install -d "$HOME/.tailscale/bin"
install -m 755 "$EXTRACT_DIR/tailscale" "$HOME/.tailscale/bin/tailscale"
install -m 755 "$EXTRACT_DIR/tailscaled" "$HOME/.tailscale/bin/tailscaled"
log "Tailscale binaries installed to $HOME/.tailscale/bin"

install -d "$HOME/.local/bin"
cat > "${TMP_DIR}/tailscale-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$HOME/.tailscale/bin/tailscale" --socket="$HOME/.tailscale/tailscaled.sock" "$@"
EOF
install -m 755 "${TMP_DIR}/tailscale-wrapper" "$HOME/.local/bin/tailscale"
log "Tailscale command wrapper installed to $HOME/.local/bin/tailscale"

if [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]]; then
  log "Note: add $HOME/.local/bin to PATH to use the tailscale command without a full path."
fi

setup_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not found; skipping systemd --user service setup."
    return
  fi

  if ! systemctl --user show-environment >/dev/null 2>&1; then
    log "systemd user services are not available in this session; skipped tailscaled.service."
    return
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
      return
    fi
  fi

  ln -sf "$managed_service" "$service_path"

  systemctl --user daemon-reload
  if systemctl --user enable tailscaled.service --now; then
    log "tailscaled.service installed and enabled."
  else
    log "tailscaled.service installed but enable/start failed. Try: systemctl --user enable --now tailscaled.service"
  fi
}

setup_service
