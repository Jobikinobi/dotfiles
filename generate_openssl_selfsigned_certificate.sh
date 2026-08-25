#!/usr/bin/env bash
# Generate a development-only self-signed certificate for an SSH3 server.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate_openssl_selfsigned_certificate.sh [options]

Options:
  --output-dir <directory>  Write cert.pem and priv.key here (default: .)
  --hostname <name>         Common name and DNS SAN (default: selfsigned.ssh3)
  --ip <address>            Add an IP subject alternative name; repeatable
  --days <days>             Certificate lifetime (default: 3660)
  -h, --help                Show this help
EOF
}

output_dir="."
hostname="selfsigned.ssh3"
days=3660
ip_addresses=()

while (($#)); do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "--output-dir requires a value" >&2; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    --hostname)
      [[ $# -ge 2 ]] || { echo "--hostname requires a value" >&2; exit 2; }
      hostname="$2"
      shift 2
      ;;
    --ip)
      [[ $# -ge 2 ]] || { echo "--ip requires a value" >&2; exit 2; }
      ip_addresses+=("$2")
      shift 2
      ;;
    --days)
      [[ $# -ge 2 ]] || { echo "--days requires a value" >&2; exit 2; }
      days="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$days" =~ ^[1-9][0-9]*$ ]] || { echo "--days must be a positive integer" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

san_entries=("DNS:${hostname}")
for ip_address in "${ip_addresses[@]}"; do
  san_entries+=("IP:${ip_address}")
done
subject_alt_name="$(IFS=,; echo "${san_entries[*]}")"

mkdir -p "$output_dir"
umask 077

openssl req -x509 -sha256 -nodes -newkey rsa:4096 \
  -keyout "$output_dir/priv.key" \
  -days "$days" \
  -out "$output_dir/cert.pem" \
  -subj "/CN=${hostname}" \
  -addext "subjectAltName=${subject_alt_name}"

echo "Created $output_dir/cert.pem and $output_dir/priv.key"
