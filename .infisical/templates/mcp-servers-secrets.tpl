# mcp-servers-secrets.tpl — secrets from the "mcp-servers" project
# Reader-only identity: can list and read, cannot modify.
#
# Environment used: dev → all MCP server credentials

{{- with listSecrets "<mcp-servers-project-id>" "dev" "/" }}
{{- range . }}
{{ .Key }}="{{ .Value }}"
{{- end }}
{{- end }}
