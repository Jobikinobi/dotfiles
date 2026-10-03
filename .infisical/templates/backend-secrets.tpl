# backend-secrets.tpl — secrets from the "backend" project
# Reader-only identity: can list and read, cannot modify.
#
# Environments used:
#   prod  → POSTMAN_API_KEY, MEM0_API_KEY      (for zshrc)
#   dev   → TAILSCALE_AUTHKEY_SERVER             (for bootstrap scripts)

{{- /* Production secrets for shell */ -}}
{{- with listSecrets "<backend-project-id>" "prod" "/" }}
{{- range . }}
{{- if or (eq .Key "POSTMAN_API_KEY") (eq .Key "MEM0_API_KEY") }}
export {{ .Key }}="{{ .Value }}"
{{- end }}
{{- end }}
{{- end }}

{{- /* Dev secrets for bootstrap */ -}}
{{- with getSecretByName "<backend-project-id>" "dev" "/" "TAILSCALE_AUTHKEY_SERVER" }}
{{ if .Value }}{{ .Value }}{{ end }}
{{- end }}
