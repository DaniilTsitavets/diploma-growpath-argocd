{{- define "growpath.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "growpath.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "growpath.selectorLabels" -}}
app.kubernetes.io/name: {{ include "growpath.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "growpath.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "growpath.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "growpath.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "growpath.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "growpath.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}

{{- define "growpath.configData" -}}
{{- $data := dict -}}
{{- range $key, $value := .Values.env -}}
{{- $_ := set $data $key (toString $value) -}}
{{- end -}}
{{- toYaml $data -}}
{{- end -}}

{{- define "growpath.hasConfig" -}}
{{- if .Values.env -}}true{{- end -}}
{{- end -}}

{{- define "growpath.envFrom" -}}
{{- if include "growpath.hasConfig" . }}
- configMapRef:
    name: {{ include "growpath.fullname" . }}
{{- end }}
{{- if .Values.externalSecret.enabled }}
- secretRef:
    name: {{ include "growpath.fullname" . }}
{{- end }}
{{- end -}}

{{- define "growpath.workingDir" -}}
{{- default (printf "/srv/services/%s" .Release.Name) .Values.workingDir -}}
{{- end -}}
