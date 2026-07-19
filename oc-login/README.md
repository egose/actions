# OpenShift oc login

Ensures `oc` is available on the runner and logs into an OpenShift cluster.

## What It Does

- Reuses an existing `oc` installation when one is already on `PATH`.
- Installs `asdf` with [`asdf-install`](../asdf-install/README.md) when `oc` is missing.
- Installs `oc` with the [`asdf-oc`](https://github.com/sqtran/asdf-oc) plugin when needed.
- Logs into the configured OpenShift cluster with either a token or username/password.
- Writes a temporary `KUBECONFIG` file and exports it for later workflow steps.
- Optionally switches the current project with `oc project` after login.

## Usage

### Login with a Token

```yaml
- name: Login to OpenShift
  uses: egose/actions/oc-login@main
  with:
    openshift_server_url: ${{ secrets.OPENSHIFT_SERVER }}
    openshift_token: ${{ secrets.OPENSHIFT_TOKEN }}
    insecure_skip_tls_verify: 'true'
```

### Login with Username and Password

```yaml
- name: Login to OpenShift with credentials
  uses: egose/actions/oc-login@main
  with:
    openshift_server_url: ${{ secrets.OPENSHIFT_SERVER }}
    openshift_username: ${{ env.OPENSHIFT_USER }}
    openshift_password: ${{ secrets.OPENSHIFT_PASSWORD }}
    certificate_authority_data: ${{ secrets.CA_DATA }}
    namespace: ${{ env.OPENSHIFT_NAMESPACE }}
```

### Pin Fallback Tool Versions

```yaml
- name: Login with pinned fallback tool versions
  uses: egose/actions/oc-login@main
  with:
    openshift_server_url: ${{ secrets.OPENSHIFT_SERVER }}
    openshift_token: ${{ secrets.OPENSHIFT_TOKEN }}
    asdf-version: v0.20.0
    oc-version: latest
```

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `openshift_server_url` | Yes | `""` | URL of the OpenShift cluster API server. |
| `openshift_token` | No | `""` | Authentication token for `oc login`. |
| `openshift_username` | No | `""` | Username for `oc login`. Overrides `openshift_token` when paired with `openshift_password`. |
| `openshift_password` | No | `""` | Password for `oc login`. Must be set with `openshift_username`. |
| `insecure_skip_tls_verify` | No | `"false"` | Skip TLS verification when `certificate_authority_data` is not provided. |
| `certificate_authority_data` | No | `""` | PEM or base64-encoded PEM certificate authority data passed to `oc login`. |
| `namespace` | No | `""` | Namespace to select with `oc project` after login. |
| `asdf-version` | No | `v0.20.0` | `asdf` version to install when `oc` is missing. |
| `oc-version` | No | `latest` | `oc` version to install with `asdf` when `oc` is missing. |

## Notes

- Either `openshift_token` or both `openshift_username` and `openshift_password` must be provided.
- When both token and username/password are set, username/password takes precedence.
- When `certificate_authority_data` is provided, it is used instead of `insecure_skip_tls_verify`.
- Existing `oc` installations are reused as-is.
