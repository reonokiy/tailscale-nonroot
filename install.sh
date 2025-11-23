# check github for the latest version
LATEST_VERSION=$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
VERSION=${1:-$LATEST_VERSION}
echo "Installing Tailscale version $VERSION"

# download the tarball to tmp and extract
TARBALL_URL="https://pkgs.tailscale.com/stable/tailscale_${VERSION}_amd64.tgz"
curl -L $TARBALL_URL -o /tmp/tailscale.tgz
mkdir -p /tmp/tailscale_extracted
tar -xzf /tmp/tailscale.tgz -C /tmp/tailscale_extracted

# move the binaries to ~/.tailscale/bin
mkdir -p ~/.tailscale/bin
mv /tmp/tailscale_extracted/tailscale ~/.tailscale/bin/
mv /tmp/tailscale_extracted/tailscaled ~/.tailscale/bin/
echo "Tailscale binaries installed to ~/.tailscale/bin/"
# alias tailscale to ~/.tailscale/bin/tailscale --socket=$HOME/.tailscale/tailscaled.sock
# add a script to ~/.local/bin/tailscale
mkdir -p ~/.local/bin
echo '#!/bin/bash' > ~/.local/bin/tailscale
echo 'export TAILSCALE_SOCKET=$HOME/.tailscale/tailscaled.sock' >> ~/.local/bin/tailscale
echo '~/.tailscale/bin/tailscale "$@"' >> ~/.local/bin/tailscale
chmod +x ~/.local/bin/tailscale
echo "Tailscale command wrapper installed to ~/.local/bin/tailscale"

# create systemd user service directory and copy service file
mkdir -p ~/.config/systemd/user/
curl -o ~/.config/systemd/user/tailscaled.service https://raw.githubusercontent.com/reonokiy/tailscale-nonroot/main/tailscaled.service
systemctl --user daemon-reload
systemctl --user enable tailscaled.service --now
echo "Tailscaled service installed and enabled."
