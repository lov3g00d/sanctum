{{/*
Resource names are pinned to "podinfo" (not release-prefixed) so the Service,
NetworkPolicy, CiliumNetworkPolicy, AnalysisTemplate and metrics job label all
resolve to the same fixed identity the recording rules and dashboards key on.
*/}}
{{- define "podinfo.name" -}}
{{- default "podinfo" .Values.nameOverride -}}
{{- end -}}

{{- define "podinfo.fullname" -}}
{{- default "podinfo" .Values.nameOverride -}}
{{- end -}}

{{- define "podinfo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "podinfo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "podinfo.name" . }}
app.kubernetes.io/component: api
{{- end -}}

{{- define "podinfo.labels" -}}
helm.sh/chart: {{ include "podinfo.chart" . }}
{{ include "podinfo.selectorLabels" . }}
app.kubernetes.io/part-of: sanctum
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "podinfo.serviceAccountName" -}}
{{- default (include "podinfo.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/*
Pod template shared verbatim by the Rollout and the Deployment fallback so the
hardened posture cannot drift between the two delivery modes.
*/}}
{{- define "podinfo.podTemplate" -}}
metadata:
  labels:
    {{- include "podinfo.selectorLabels" . | nindent 4 }}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9898"
    prometheus.io/path: {{ .Values.config.metricsPath | quote }}
spec:
  serviceAccountName: {{ include "podinfo.serviceAccountName" . }}
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: {{ .Values.topologySpread.whenUnsatisfiable }}
      labelSelector:
        matchLabels:
          {{- include "podinfo.selectorLabels" . | nindent 10 }}
  containers:
    - name: podinfo
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      ports:
        - name: http
          containerPort: 9898
          protocol: TCP
      env:
        # Setting otel-service-name is what switches podinfo's tracing on; the
        # OTLP gRPC exporter then reads OTEL_EXPORTER_OTLP_ENDPOINT. The http://
        # scheme selects an insecure (non-TLS) connection to the collector.
        - name: PODINFO_OTEL_SERVICE_NAME
          value: podinfo
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: {{ .Values.otel.endpoint | quote }}
      envFrom:
        - configMapRef:
            name: {{ include "podinfo.fullname" . }}-config
        - secretRef:
            name: {{ include "podinfo.fullname" . }}-secrets
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      startupProbe:
        httpGet:
          path: /readyz
          port: http
        periodSeconds: 5
        failureThreshold: 30
      livenessProbe:
        httpGet:
          path: /healthz
          port: http
        initialDelaySeconds: 0
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 3
      readinessProbe:
        httpGet:
          path: /readyz
          port: http
        initialDelaySeconds: 0
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 3
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        capabilities:
          drop:
            - ALL
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir:
        sizeLimit: 64Mi
{{- end -}}
