#!/usr/bin/env bash

set -euo pipefail

is_truthy() {
  case "${1:-}" in
    true|TRUE|True|1|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

decode_base64() {
  if printf 'Zm9v' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
    return
  fi

  if printf 'Zm9v' | base64 -d >/dev/null 2>&1; then
    base64 -d
    return
  fi

  base64 -D
}

server_url="${OCLOGIN_SERVER_URL:-}"
token="${OCLOGIN_TOKEN:-}"
username="${OCLOGIN_USERNAME:-}"
password="${OCLOGIN_PASSWORD:-}"
ca_data="${OCLOGIN_CERTIFICATE_AUTHORITY_DATA:-}"
namespace="${OCLOGIN_NAMESPACE:-}"
insecure_skip_tls_verify="${OCLOGIN_INSECURE_SKIP_TLS_VERIFY:-false}"

if [ -z "$server_url" ]; then
  echo "❌ openshift_server_url is required"
  exit 1
fi

if [ -n "$username" ] || [ -n "$password" ]; then
  if [ -z "$username" ] || [ -z "$password" ]; then
    echo "❌ openshift_username and openshift_password must both be provided"
    exit 1
  fi

  auth_mode="username_password"
elif [ -n "$token" ]; then
  auth_mode="token"
else
  echo "❌ Provide openshift_token or both openshift_username and openshift_password"
  exit 1
fi

kubeconfig_path="${RUNNER_TEMP}/oc-login-kubeconfig"
mkdir -p "$(dirname "$kubeconfig_path")"
: > "$kubeconfig_path"
chmod 600 "$kubeconfig_path"
echo "KUBECONFIG=$kubeconfig_path" >> "$GITHUB_ENV"
export KUBECONFIG="$kubeconfig_path"

login_args=(login "--server=${server_url}")

if [ "$auth_mode" = "username_password" ]; then
  login_args+=("--username=${username}" "--password=${password}")
else
  login_args+=("--token=${token}")
fi

if [ -n "$ca_data" ]; then
  ca_file="${RUNNER_TEMP}/oc-login-ca.crt"

  case "$ca_data" in
    *"-----BEGIN "*)
      printf '%s\n' "$ca_data" > "$ca_file"
      ;;
    *)
      if ! printf '%s' "$ca_data" | decode_base64 > "$ca_file" 2>/dev/null; then
        echo "❌ certificate_authority_data must be PEM data or base64-encoded PEM"
        exit 1
      fi
      ;;
  esac

  login_args+=("--certificate-authority=${ca_file}")
elif is_truthy "$insecure_skip_tls_verify"; then
  login_args+=("--insecure-skip-tls-verify=true")
fi

oc "${login_args[@]}"

if [ -n "$namespace" ]; then
  oc project "$namespace"
fi
