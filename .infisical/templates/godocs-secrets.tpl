# godocs-secrets.tpl — secrets from the "godocs" project
# Reader-only identity: can list and read, cannot modify.
#
# Environment used: dev → R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ACCOUNT_ID

{{- with listSecrets "<godocs-project-id>" "dev" "/" }}
{{- range . }}
{{- if or (eq .Key "R2_ACCESS_KEY_ID") (eq .Key "R2_SECRET_ACCESS_KEY") (eq .Key "R2_ACCOUNT_ID") }}
{{ .Key }}="{{ .Value }}"
{{- end }}
{{- end }}
{{- end }}
