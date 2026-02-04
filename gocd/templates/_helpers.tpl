{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "gocd.name" -}}
{{- default .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gocd.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "gocd.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "gocd.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use for agents
*/}}
{{- define "gocd.agentServiceAccountName" -}}
{{- if .Values.agent.serviceAccount.reuseTopLevelServiceAccount -}}
    {{ template "gocd.serviceAccountName" . }}
{{- else -}}
    {{ default "default" .Values.agent.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gocd.labels" -}}
helm.sh/chart: {{ include "gocd.name" . }}
app.kubernetes.io/name: {{ include "gocd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
=============================================================================
PRIVATE CA HELPERS
=============================================================================
*/}}

{{/*
Determine if private CA is enabled and has a valid source
*/}}
{{- define "gocd.privateCA.enabled" -}}
{{- if .Values.global.privateCA.enabled -}}
{{- if or .Values.global.privateCA.existingSecret.name .Values.global.privateCA.existingConfigMap.name -}}
true
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Get the CA source volume definition
*/}}
{{- define "gocd.privateCA.volume" -}}
{{- if .Values.global.privateCA.existingSecret.name }}
- name: enterprise-ca-bundle
  secret:
    secretName: {{ .Values.global.privateCA.existingSecret.name }}
    items:
      - key: {{ .Values.global.privateCA.existingSecret.key | default "ca-bundle.crt" }}
        path: ca-bundle.crt
{{- else if .Values.global.privateCA.existingConfigMap.name }}
- name: enterprise-ca-bundle
  configMap:
    name: {{ .Values.global.privateCA.existingConfigMap.name }}
    items:
      - key: {{ .Values.global.privateCA.existingConfigMap.key | default "ca.crt" }}
        path: ca-bundle.crt
{{- end }}
{{- if .Values.global.privateCA.javaTruststore.enabled }}
- name: java-truststore
  emptyDir: {}
{{- end }}
{{- end -}}

{{/*
Get CA volume mounts
*/}}
{{- define "gocd.privateCA.volumeMounts" -}}
- name: enterprise-ca-bundle
  mountPath: {{ .Values.global.privateCA.mountPaths.caBundlePEM | default "/etc/ssl/certs/enterprise-ca-bundle.crt" }}
  subPath: ca-bundle.crt
  readOnly: true
{{- if .Values.global.privateCA.javaTruststore.enabled }}
- name: java-truststore
  mountPath: {{ .Values.global.privateCA.mountPaths.javaTruststore | default "/etc/ssl/certs/java/cacerts" }}
  subPath: cacerts
  readOnly: true
{{- end }}
{{- end -}}

{{/*
Get CA environment variables
*/}}
{{- define "gocd.privateCA.envVars" -}}
{{- $caPath := .Values.global.privateCA.mountPaths.caBundlePEM | default "/etc/ssl/certs/enterprise-ca-bundle.crt" -}}
{{- range $name, $value := .Values.global.privateCA.environmentVariables }}
- name: {{ $name }}
  value: {{ $value | quote }}
{{- end }}
{{- if .Values.global.privateCA.javaTruststore.enabled }}
- name: JAVA_TOOL_OPTIONS
  value: "-Djavax.net.ssl.trustStore={{ $.Values.global.privateCA.mountPaths.javaTruststore | default "/etc/ssl/certs/java/cacerts" }} -Djavax.net.ssl.trustStorePassword={{ $.Values.global.privateCA.javaTruststore.password | default "changeit" }}"
{{- end }}
{{- end -}}

{{/*
Init container to generate Java truststore from CA bundle
*/}}
{{- define "gocd.privateCA.truststoreInitContainer" -}}
{{- $image := .Values.global.elasticAgentCAInjection.initContainerImage | default "eclipse-temurin:17-jdk" -}}
{{- if .Values.global.airgap.enabled }}
{{- $image = printf "%s/%s" .Values.global.airgap.imageRegistry $image -}}
{{- end }}
- name: generate-truststore
  image: {{ $image }}
  command:
    - /bin/sh
    - -c
    - |
      set -e
      echo "Copying default Java truststore..."
      cp $JAVA_HOME/lib/security/cacerts /truststore/cacerts
      chmod 644 /truststore/cacerts

      echo "Importing enterprise CA certificate..."
      keytool -importcert -noprompt \
        -keystore /truststore/cacerts \
        -storepass {{ .Values.global.privateCA.javaTruststore.password | default "changeit" }} \
        -alias enterprise-root-ca \
        -file /ca-source/ca-bundle.crt

      echo "Truststore generation complete."
      keytool -list -keystore /truststore/cacerts \
        -storepass {{ .Values.global.privateCA.javaTruststore.password | default "changeit" }} \
        | grep -i enterprise || true
  volumeMounts:
    - name: enterprise-ca-bundle
      mountPath: /ca-source
      readOnly: true
    - name: java-truststore
      mountPath: /truststore
{{- end -}}

{{/*
=============================================================================
AIRGAP PLUGIN MIRROR HELPERS
=============================================================================
*/}}

{{/*
Init container to download plugins from internal mirror
*/}}
{{- define "gocd.airgap.pluginDownloadInitContainer" -}}
{{- if and .Values.global.airgap.enabled .Values.global.airgap.pluginMirror.enabled }}
- name: download-plugins
  image: {{ if .Values.global.airgap.imageRegistry }}{{ .Values.global.airgap.imageRegistry }}/{{ end }}curlimages/curl:latest
  command:
    - /bin/sh
    - -c
    - |
      set -e
      MIRROR_URL="{{ .Values.global.airgap.pluginMirror.baseUrl }}"
      PLUGIN_DIR="/godata/plugins/external"

      mkdir -p "$PLUGIN_DIR"

      {{- if and .Values.global.airgap.pluginMirror.auth.enabled .Values.global.airgap.pluginMirror.auth.existingSecret }}
      AUTH_OPTS="--user $(cat /auth/{{ .Values.global.airgap.pluginMirror.auth.usernameKey }}):$(cat /auth/{{ .Values.global.airgap.pluginMirror.auth.passwordKey }})"
      {{- else }}
      AUTH_OPTS=""
      {{- end }}

      {{- if eq (include "gocd.privateCA.enabled" .) "true" }}
      CA_OPTS="--cacert /ca/ca-bundle.crt"
      {{- else }}
      CA_OPTS=""
      {{- end }}

      {{- range .Values.global.airgap.pluginMirror.plugins }}
      echo "Downloading {{ . }}..."
      curl -fsSL $AUTH_OPTS $CA_OPTS \
        "${MIRROR_URL}/{{ . }}" \
        -o "${PLUGIN_DIR}/{{ . }}"
      {{- end }}

      echo "Plugin download complete:"
      ls -la "$PLUGIN_DIR"
  volumeMounts:
    - name: goserver-vol
      mountPath: /godata
      subPath: {{ .Values.server.persistence.subpath.godata }}
    {{- if eq (include "gocd.privateCA.enabled" .) "true" }}
    - name: enterprise-ca-bundle
      mountPath: /ca
      readOnly: true
    {{- end }}
    {{- if and .Values.global.airgap.pluginMirror.auth.enabled .Values.global.airgap.pluginMirror.auth.existingSecret }}
    - name: plugin-mirror-auth
      mountPath: /auth
      readOnly: true
    {{- end }}
{{- end }}
{{- end -}}

{{/*
=============================================================================
GIT CONFIG HELPERS
=============================================================================
*/}}

{{/*
Generate .gitconfig content
*/}}
{{- define "gocd.gitconfig.content" -}}
[http]
{{- if eq (include "gocd.privateCA.enabled" .) "true" }}
    sslCAInfo = {{ .Values.global.privateCA.mountPaths.caBundlePEM | default "/etc/ssl/certs/enterprise-ca-bundle.crt" }}
{{- end }}
    sslVerify = true

{{- range .Values.global.airgap.git.urlRewrites }}
[url "{{ .replacement }}"]
    insteadOf = {{ .original }}
{{- end }}

{{ .Values.global.airgap.git.extraConfig }}
{{- end -}}

{{/*
=============================================================================
IMAGE HELPERS (with airgap registry override)
=============================================================================
*/}}

{{/*
Get full image reference with optional registry override
*/}}
{{- define "gocd.image" -}}
{{- $registry := "" -}}
{{- if .global.airgap.enabled -}}
{{- $registry = .global.airgap.imageRegistry -}}
{{- end -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry .repository .tag -}}
{{- else -}}
{{- printf "%s:%s" .repository .tag -}}
{{- end -}}
{{- end -}}
