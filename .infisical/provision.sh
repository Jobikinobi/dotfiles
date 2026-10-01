#!/usr/bin/env bash
# provision.sh — Bootstrap Infisical infrastructure for dotfiles.
#
# This script is run ONCE (idempotent) by a human operator who has access to
# the Infisical **Provisioner** machine identity. That identity must have:
#   - Organization-level role that can create projects
#   - Project-level "admin" or custom role on all target projects
#   - Ability to create child machine identities and assign them roles
#
# The Provisioner identity NEVER reads secret values. It only provisions:
#   1. Projects (backend, godocs, mcp-servers) with required environments
#   2. Child machine identities scoped to individual projects (reader-only)
#   3. Age-encrypts each child identity's client-id / client-secret
#
# After provisioning, the child credentials live in .infisical/children/<name>/
# under git (age-encrypted). The daemon configs reference these files.

set -euo pipefail

PROG="$(basename "$0")"
INFISICAL_DIR="$(cd "$(dirname "$0")" && pwd)"
CHILDREN_DIR="$INFISICAL_DIR/children"
REPO_ROOT="$(cd "$INFISICAL_DIR/../.." && pwd)"

# ──────────────────────────────────────────────────────────────────────────────
# Configuration — override via environment or edit below
# ──────────────────────────────────────────────────────────────────────────────

# Path to the Provisioner's Universal Auth credentials (human-held, never encrypted in repo).
PROVISIONER_CLIENT_ID="${INFISICAL_PROVISIONER_CLIENT_ID:-}"
PROVISIONER_CLIENT_SECRET="${INFISICAL_PROVISIONER_CLIENT_SECRET:-}"
INFISICAL_ADDRESS="${INFISICAL_ADDRESS:-https://app.infisical.com}"

# Which projects to ensure exist. Each entry: "<slug>:<env1>,<env2>"
PROJECTS=(
  "backend:dev,prod"
  "godocs:dev"
  "mcp-servers:dev"
)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$*"; exit 1; }

info() { printf '→ %s\n' "$*" >&2; }

# Authenticate as the Provisioner and return a Bearer token.
provisioner_token() {
  if [[ -z "$PROVISIONER_CLIENT_ID" || -z "$PROVISIONER_CLIENT_SECRET" ]]; then
    die "Set INFISICAL_PROVISIONER_CLIENT_ID and INFISICAL_PROVISIONER_CLIENT_SECRET env vars."
  fi

  local resp
  resp="$(curl -sf -X POST "$INFISICAL_ADDRESS/api/v1/auth/universal-auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"clientId\":\"$PROVISIONER_CLIENT_ID\",\"clientSecret\":\"$PROVISIONER_CLIENT_SECRET\"}")" || \
    die "Failed to authenticate as Provisioner. Check credentials."

  echo "$resp" | jq -r '.accessToken'
}

# Ensure a project exists; return its UUID.
ensure_project() {
  local slug="$1" token="$2"
  local resp
  resp="$(curl -sf "$INFISICAL_ADDRESS/api/v1/projects?includeRoles=true" \
    -H "Authorization: Bearer $token")" || \
    die "Failed to list projects."

  local existing
  existing="$(echo "$resp" | jq -r --arg s "$slug" \
    '.projects[] | select(.slug == $s) | .id')"

  if [[ -n "$existing" ]]; then
    info "Project '$slug' already exists (id: $existing)"
    echo "$existing"
    return
  fi

  info "Creating project '$slug'..."
  local create_resp
  create_resp="$(curl -sf -X POST "$INFISICAL_ADDRESS/api/v1/projects" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$slug\",\"slug\":\"$slug\"}")" || \
    die "Failed to create project '$slug'."

  echo "$create_resp" | jq -r '.project.id'
}

# Ensure environments exist on a project.
ensure_environments() {
  local project_id="$1" envs_csv="$2" token="$3"
  IFS=',' read -ra envs <<< "$envs_csv"
  for env in "${envs[@]}"; do
    # Environments are auto-created when secrets are first set, but we log it.
    info "  Environment '$env' should exist on project '$project_id'"
  done
}

# Create (or ensure exists) a child machine identity with reader role on a project.
# Returns the child's client-id and client-secret on stdout, one per line.
ensure_child_identity() {
  local project_id="$1" child_name="$2" token="$3"

  # Check if child identity already exists on this project.
  local resp
  resp="$(curl -sf "$INFISICAL_ADDRESS/api/v1/projects/$project_id/identities?offset=0&limit=100" \
    -H "Authorization: Bearer $token")" || \
    die "Failed to list identities for project $project_id."

  local existing_id
  existing_id="$(echo "$resp" | jq -r --arg n "$child_name" \
    '.identities[] | select(.identity.name == $n) | .identity.id')"

  if [[ -n "$existing_id" ]]; then
    info "Child identity '$child_name' already exists (id: $existing_id)"
    echo "$existing_id"
    return 0
  fi

  info "Creating child identity '$child_name' for project '$project_id'..."
  local create_resp
  create_resp="$(curl -sf -X POST "$INFISICAL_ADDRESS/api/v1/identities" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"dotfiles-$child_name\"}")" || \
    die "Failed to create child identity."

  local new_id
  new_id="$(echo "$create_resp" | jq -r '.identity.id')"

  # Add Universal Auth method to the child identity.
  curl -sf -X POST "$INFISICAL_ADDRESS/api/v1/auth/universal-auth/identities/$new_id" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{}' >/dev/null || \
    die "Failed to add Universal Auth to child identity."

  # Assign reader role on the project.
  # Uses the organization-level membership endpoint.
  curl -sf -X POST "$INFISICAL_ADDRESS/api/v1/organization/identities/memberships" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"identityId\":\"$new_id\",\"projectId\":\"$project_id\",\"roleSlug\":\"reader\"}" >/dev/null || \
    die "Failed to assign reader role to child identity."

  echo "$new_id"
}

# Fetch and age-encrypt child credentials.
store_child_credentials() {
  local identity_id="$1" child_name="$2" token="$3"
  local child_dir="$CHILDREN_DIR/$child_name"
  mkdir -p "$child_dir"

  # Get the Universal Auth client-id/client-secret for this identity.
  local auth_resp
  auth_resp="$(curl -sf "$INFISICAL_ADDRESS/api/v1/auth/universal-auth/identities/$identity_id" \
    -H "Authorization: Bearer $token")" || \
    die "Failed to get auth config for identity $identity_id."

  local client_id client_secret
  client_id="$(echo "$auth_resp" | jq -r '.clientId')"
  client_secret="$(echo "$auth_resp" | jq -r '.clientSecret')"

  if [[ -z "$client_id" || -z "$client_secret" ]]; then
    die "No credentials returned for identity $identity_id."
  fi

  # Write plaintext credentials (will be encrypted immediately).
  printf '%s' "$client_id" > "$child_dir/client-id"
  printf '%s' "$client_secret" > "$child_dir/client-secret"

  # Age-encrypt using the chezmoi key (the same key used for all repo secrets).
  local age_key="${INFISICAL_AGE_KEY_PATH:-$HOME/.config/chezmoi/key.txt}"
  if [[ ! -f "$age_key" ]]; then
    die "Age key not found at $age_key. Set INFISICAL_AGE_KEY_PATH."
  fi

  age -d -i "$age_key" < /dev/null >/dev/null 2>&1 || \
    die "Cannot decrypt with age key — is it valid?"

  age -e -r "$(age -d -i "$age_key" 2>/dev/null | head -1 || \
    grep -oP 'age1[^ ]+' "$age_key" 2>/dev/null | head -1)" \
    -o "$child_dir/client-id.age" "$child_dir/client-id" 2>/dev/null || {
    # Fallback: try reading recipient from the key file directly
    local recipient
    recipient="$(cat "$age_key" 2>/dev/null | grep -oP 'age1[^ ]+' | head -1)"
    if [[ -n "$recipient" ]]; then
      age -e -r "$recipient" -o "$child_dir/client-id.age" "$child_dir/client-id"
      age -e -r "$recipient" -o "$child_dir/client-secret.age" "$child_dir/client-secret"
    else
      die "Could not determine age recipient from key file. Run: age -d -i $age_key"
    fi
  }

  rm -f "$child_dir/client-id" "$child_dir/client-secret"

  chmod 600 "$child_dir"/*.age
  info "Credentials for '$child_name' stored age-encrypted in $child_dir/"
}

# Generate a child agent config for a given project.
generate_child_config() {
  local child_name="$1" project_slug="$2"
  local child_dir="$CHILDREN_DIR/$child_name"

  cat > "$INFISICAL_DIR/agent-${child_name}.yaml" <<EOF
# Infisical Agent config for the '$child_name' project.
# This identity is reader-only — it can fetch secrets but cannot create or modify anything.
# Credentials are age-encrypted in $child_dir/

infisical:
  address: "$INFISICAL_ADDRESS"
  exit-after-auth: false
  revoke-credentials-on-shutdown: false
  retry-strategy:
    max-retries: 5
    max-delay: "10s"
    base-delay: "500ms"

auth:
  type: "universal-auth"
  config:
    client-id: "$child_dir/client-id.age"
    client-secret: "$child_dir/client-secret.age"

templates:
  - source-path: "./templates/${child_name}-secrets.tpl"
    destination-path: "{{ .chezmoi.homeDir }}/.infisical/${child_name}-secrets.env"
    config:
      polling-interval: "5m"
EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

main() {
  info "Infisical provisioner bootstrap"
  info "Address: $INFISICAL_ADDRESS"

  local token
  token="$(provisioner_token)"

  for project_spec in "${PROJECTS[@]}"; do
    IFS=':' read -r slug envs_csv <<< "$project_spec"
    info "Processing project: $slug (environments: $envs_csv)"

    local project_id
    project_id="$(ensure_project "$slug" "$token")"

    ensure_environments "$project_id" "$envs_csv" "$token"

    local child_id
    child_id="$(ensure_child_identity "$project_id" "dotfiles-agent" "$token")"

    store_child_credentials "$child_id" "$slug" "$token"

    generate_child_config "$slug" "$slug"
  done

  info ""
  info "Provisioning complete."
  info "Next steps:"
  info "  1. Copy .infisical/agent-<project>.yaml → ~/.config/infisical/agent-<project>.yaml"
  info "  2. Start each agent: infisical agent --config ~/.config/infisical/agent-<project>.yaml"
  info "  3. Verify rendered files: ls ~/.infisical/*-secrets.env"
}

main "$@"
