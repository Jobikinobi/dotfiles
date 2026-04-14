#!/bin/sh
# Entrypoint: start Tailscale, then sshd
# Pass TS_AUTHKEY as env var at runtime: docker run -e TS_AUTHKEY=tskey-auth-...

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state \
  --socket=/var/run/tailscale/tailscaled.sock &

# Wait for tailscaled to be ready
sleep 2

# Join tailnet if auth key is provided
if [ -n "$TS_AUTHKEY" ]; then
  /usr/local/bin/tailscale up --authkey="$TS_AUTHKEY" --ssh --hostname="${TS_HOSTNAME:-dotfiles-test}"
  echo "✓ Tailscale connected"
else
  echo "⚠ No TS_AUTHKEY — Tailscale not started. Pass -e TS_AUTHKEY=... to join tailnet."
fi

# Start sshd in foreground
exec /usr/sbin/sshd -D
