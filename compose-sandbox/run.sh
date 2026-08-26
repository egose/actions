#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# Run repo-toolkit-compose-sandbox lifecycle engine.
# Inputs are sourced from COMPOSE_SANDBOX_INPUT_* env vars set by action.yml.
# No caller-controlled string is evaluated as shell source; CLI is built
# with Bash arrays. Version resolution is pinned to an exact semver.
# ----------------------------------------------------------------------------

COMPOSE_SANDBOX_RESOLVED_BIN=""

validate_semver() {
  local v="$1"
  local label="$2"
  if [[ -z "$v" ]]; then
    echo "❌ $label must be an exact semver, got empty" >&2
    return 1
  fi
  if [[ "$v" == "latest" ]]; then
    echo "❌ $label must be an exact semver, got 'latest' (pinned version required)" >&2
    return 1
  fi
  # semver: X.Y.Z with optional prerelease/build
  if ! [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
    echo "❌ $label must be an exact semver (e.g. 0.18.0), got: $v" >&2
    return 1
  fi
  if [[ "$v" == *".."* || "$v" == *"//"* ]]; then
    echo "❌ $label contains invalid sequence: $v" >&2
    return 1
  fi
}

validate_artifact_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "❌ artifact-name must be non-empty" >&2
    return 1
  fi
  if [[ "$name" == *"/"* ]]; then
    echo "❌ artifact-name must not contain path separators: $name" >&2
    return 1
  fi
  if [[ "$name" == *"\\"* ]]; then
    echo "❌ artifact-name must not contain path separators: $name" >&2
    return 1
  fi
  # NUL check is unnecessary in Bash (env vars cannot contain NUL) and would
  # incorrectly match every string because $'\0' expands to empty. Skip.
  # GitHub artifact names: printable, no colon, no slash, limited length
  if ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    # Allow hyphens, dots, underscores between alphanum; reject spaces/slashes
    # Example from spec: integration-service-logs-1 is valid. We keep strict
    # so malicious names cannot escape.
    echo "❌ artifact-name must match ^[A-Za-z0-9._-]+\\$ : $name" >&2
    return 1
  fi
  if [[ ${#name} -gt 100 ]]; then
    echo "❌ artifact-name must be <=100 chars" >&2
    return 1
  fi
}

validate_retention() {
  local v="$1"
  if [[ -z "$v" ]]; then
    return 0
  fi
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "❌ artifact-retention-days must be a positive integer, got: $v" >&2
    return 1
  fi
  if [[ "$v" -lt 1 || "$v" -gt 90 ]]; then
    echo "❌ artifact-retention-days must be 1-90, got: $v" >&2
    return 1
  fi
}

resolve_path() {
  local base="$1"
  local target="$2"
  local label="$3"
  # NUL cannot be represented in Bash strings; env vars never contain NUL.
  # The toolkit validates path NULs separately.
  local joined
  if [[ "$target" == /* ]]; then
    joined="$target"
  else
    joined="${base%/}/${target}"
  fi
  # Use realpath -m if available (does not require existence), else python3, else naive
  local resolved=""
  if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    resolved="$(realpath -m "$joined" 2>/dev/null || echo "$joined")"
  elif command -v python3 >/dev/null 2>&1; then
    resolved="$(python3 -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])) if not os.path.isabs(sys.argv[2]) else os.path.normpath(sys.argv[2]))' "$base" "$target" 2>/dev/null || echo "$joined")"
  else
    resolved="$joined"
  fi
  # Trim trailing slash except root
  if [[ "$resolved" != "/" ]]; then
    resolved="${resolved%/}"
  fi
  echo "$resolved"
}

ensure_asdf_available() {
  if command -v asdf >/dev/null 2>&1; then
    return 0
  fi
  # Try common asdf locations
  if [[ -x "$HOME/.asdf/bin/asdf" ]]; then
    export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"
    if command -v asdf >/dev/null 2>&1; then return 0; fi
  fi
  if [[ -x "/opt/asdf-vm/bin/asdf" ]]; then
    export PATH="/opt/asdf-vm/bin:$PATH"
    if command -v asdf >/dev/null 2>&1; then return 0; fi
  fi
  # Fall back to installing via asdf-install if available
  local asdf_version="v0.15.0"
  local install_sh="${COMPOSE_SANDBOX_ACTION_PATH:?}/../asdf-install/install.sh"
  if [[ -f "$install_sh" ]]; then
    echo >&2 "➡️ Installing asdf ${asdf_version} for repo-toolkit..."
    ASDF_VERSION="${asdf_version}" bash "$install_sh" >&2 || return 1
    export PATH="${RUNNER_TEMP:-/tmp}/asdf-bin:${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
    if command -v asdf >/dev/null 2>&1; then return 0; fi
  fi
  echo >&2 "❌ asdf is unavailable and could not be installed"
  return 1
}

install_repo_toolkit_via_asdf() {
  if command -v repo-toolkit-compose-sandbox >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo >&2 "⚠️ jq not found; cannot install repo-toolkit via asdf (requires jq)."
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo >&2 "⚠️ node not found; cannot install repo-toolkit via asdf."
    return 1
  fi
  ensure_asdf_available || return 1

  local toolkit_version="${COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION:-0.18.0}"
  local toolkit_plugin_url="${COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_PLUGIN_URL:-https://github.com/egose/repo-toolkit.git}"
  validate_semver "$toolkit_version" "repo-toolkit-version" || return 1
  COMPOSE_SANDBOX_RESOLVED_BIN=""

  if ! asdf plugin list 2>/dev/null | grep -q "^repo-toolkit$"; then
    asdf plugin add repo-toolkit "$toolkit_plugin_url" >&2 || true
  fi

  echo >&2 "➡️ repo-toolkit-compose-sandbox not found; installing repo-toolkit ${toolkit_version} via asdf..."

  if ! asdf install repo-toolkit "$toolkit_version" >&2; then
    echo >&2 "⚠️ asdf repo-toolkit install failed for version ${toolkit_version}"
    return 1
  fi

  local direct_bin="${ASDF_DATA_DIR:-$HOME/.asdf}/installs/repo-toolkit/${toolkit_version}/bin/repo-toolkit-compose-sandbox"
  if [[ -n "$toolkit_version" ]]; then
    asdf set -u repo-toolkit "$toolkit_version" >&2 || true
  fi
  local shims_dir="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$shims_dir" >> "$GITHUB_PATH" 2>/dev/null || true
  fi
  export PATH="$shims_dir:$PATH"
  asdf reshim repo-toolkit >&2 || asdf reshim >&2 || true

  if asdf which repo-toolkit-compose-sandbox >/dev/null 2>&1 && command -v repo-toolkit-compose-sandbox >/dev/null 2>&1; then
    echo >&2 "✅ repo-toolkit ${toolkit_version} installed via asdf"
    return 0
  fi
  if [[ -x "$direct_bin" ]]; then
    echo >&2 "✅ repo-toolkit ${toolkit_version} installed via asdf (direct bin)"
    COMPOSE_SANDBOX_RESOLVED_BIN="$direct_bin"
    return 0
  fi
  echo >&2 "⚠️ repo-toolkit-compose-sandbox still not found after asdf install"
  return 1
}

resolve_binary() {
  # 1. Explicit override
  if [[ -n "${COMPOSE_SANDBOX_INPUT_BIN:-}" ]]; then
    local bin_input="${COMPOSE_SANDBOX_INPUT_BIN}"
    if [[ -x "$bin_input" ]]; then
      echo "$bin_input"
      return 0
    fi
    if command -v "$bin_input" >/dev/null 2>&1; then
      # command -v resolves via PATH; still validate it is not empty
      local resolved
      resolved="$(command -v "$bin_input" 2>/dev/null || echo "$bin_input")"
      echo "$resolved"
      return 0
    fi
    echo >&2 "❌ compose-sandbox-bin override not found or not executable: $bin_input"
    return 1
  fi

  # 2. Workspace node_modules/.bin
  local ws_root="${GITHUB_WORKSPACE:-$(pwd)}"
  local candidates=()
  candidates+=("$ws_root/node_modules/.bin/repo-toolkit-compose-sandbox")
  # Also try cwd-relative lookup (runner workspace may differ from cwd)
  local cwd_hint="${COMPOSE_SANDBOX_INPUT_CWD:-$ws_root}"
  if [[ "$cwd_hint" != "$ws_root" ]]; then
    # Resolve cwd_hint to absolute for lookup; best effort without validation yet
    local cwd_abs_hint
    cwd_abs_hint="$(resolve_path "$ws_root" "$cwd_hint" "cwd" 2>/dev/null || echo "$cwd_hint")"
    candidates+=("$cwd_abs_hint/node_modules/.bin/repo-toolkit-compose-sandbox")
  fi
  for cand in "${candidates[@]}"; do
    if [[ -n "$cand" && -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done

  # 3. ACTION_PATH node_modules/.bin
  local action_bin="${COMPOSE_SANDBOX_ACTION_PATH:-}/node_modules/.bin/repo-toolkit-compose-sandbox"
  if [[ -n "$action_bin" && -x "$action_bin" ]]; then
    echo "$action_bin"
    return 0
  fi

  # 4. PATH lookup (includes asdf shims)
  if command -v repo-toolkit-compose-sandbox >/dev/null 2>&1; then
    echo "repo-toolkit-compose-sandbox"
    return 0
  fi

  # 5. asdf fallback with exact version
  if install_repo_toolkit_via_asdf; then
    if [[ -n "${COMPOSE_SANDBOX_RESOLVED_BIN:-}" && -x "${COMPOSE_SANDBOX_RESOLVED_BIN}" ]]; then
      echo "${COMPOSE_SANDBOX_RESOLVED_BIN}"
      return 0
    fi
    if command -v repo-toolkit-compose-sandbox >/dev/null 2>&1; then
      echo "repo-toolkit-compose-sandbox"
      return 0
    fi
  fi

  echo >&2 "❌ repo-toolkit-compose-sandbox not found. Install it via pnpm add -D @repo-toolkit/compose-sandbox@${COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION:-0.18.0} or ensure asdf is available."
  return 1
}

find_manifest() {
  local cwd_abs="$1"
  # Try known defaults first for speed
  local candidates=(
    "$cwd_abs/.compose-sandbox-logs/result.json"
    "$cwd_abs/.ci-logs/result.json"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  # Fallback: find any result.json within cwd (max depth 4)
  local found=""
  if command -v find >/dev/null 2>&1; then
    found="$(find "$cwd_abs" -maxdepth 4 -type f -name "result.json" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$found" && -f "$found" ]]; then
      echo "$found"
      return 0
    fi
  fi
  # Last resort: check evidence dir derived from config? skip
  return 1
}

parse_manifest_field() {
  local manifest="$1"
  local field="$2"
  # Use python3 for safe JSON parsing without eval
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$manifest" "$field" <<'PY' 2>/dev/null || echo ""
import json, sys
path = sys.argv[1]
field = sys.argv[2]
try:
  with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
  val = data.get(field, "")
  if isinstance(val, str):
    print(val)
  elif val is None:
    print("")
  else:
    # For phase/outcome etc, coerce to string but avoid dumping objects
    if isinstance(val, (dict, list)):
      print("")
    else:
      print(str(val))
except Exception:
  print("")
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg f "$field" '.[$f] // empty' "$manifest" 2>/dev/null | head -n 1 || echo ""
  else
    echo ""
  fi
}

sanitize_for_output() {
  # Strip ANSI, truncate, and ensure no newlines in single-line outputs
  local v="$1"
  # Remove ANSI sequences
  if command -v sed >/dev/null 2>&1; then
    v="$(printf '%s' "$v" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' 2>/dev/null || printf '%s' "$v")"
  fi
  # Remove newlines and carriage returns for GITHUB_OUTPUT single line
  v="${v//$'\n'/ }"
  v="${v//$'\r'/ }"
  # Truncate to 2000 chars
  if [[ ${#v} -gt 2000 ]]; then
    v="${v:0:2000}"
  fi
  # Also strip leading/trailing whitespace
  v="$(printf '%s' "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' 2>/dev/null || printf '%s' "$v")"
  printf '%s' "$v"
}

main() {
  local config_input="${COMPOSE_SANDBOX_INPUT_CONFIG:-}"
  if [[ -z "$config_input" ]]; then
    echo >&2 "❌ config input is required"
    exit 1
  fi
  local policy="${COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY:-failure}"
  case "$policy" in
    failure|always|never) ;;
    *)
      echo >&2 "❌ artifact-policy must be one of failure, always, never; got: $policy"
      exit 1
      ;;
  esac

  local artifact_name_input="${COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME:-compose-sandbox-logs}"
  if [[ "$policy" != "never" && -n "$artifact_name_input" ]]; then
    validate_artifact_name "$artifact_name_input" || exit 1
  fi

  local retention="${COMPOSE_SANDBOX_INPUT_ARTIFACT_RETENTION_DAYS:-}"
  validate_retention "$retention" || exit 1

  local version_input="${COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION:-0.18.0}"
  validate_semver "$version_input" "repo-toolkit-version" || exit 1

  local cwd_input="${COMPOSE_SANDBOX_INPUT_CWD:-${GITHUB_WORKSPACE:-$(pwd)}}"
  if [[ -z "$cwd_input" ]]; then
    cwd_input="$(pwd)"
  fi
  # Resolve cwd to absolute canonical path (requires existence)
  local cwd_abs=""
  if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
    cwd_abs="$(realpath -m "$cwd_input" 2>/dev/null || echo "$cwd_input")"
  elif command -v python3 >/dev/null 2>&1; then
    cwd_abs="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$cwd_input" 2>/dev/null || echo "$cwd_input")"
  else
    cwd_abs="$cwd_input"
  fi
  # For existence check, use realpath without -m if possible, but allow -m result
  # Ensure cwd exists and is directory
  if [[ ! -d "$cwd_abs" ]]; then
    # Try resolving relative to workspace if not absolute
    if [[ "$cwd_abs" != /* && -n "${GITHUB_WORKSPACE:-}" ]]; then
      local alt
      alt="$(resolve_path "$GITHUB_WORKSPACE" "$cwd_input" "cwd" 2>/dev/null || echo "")"
      if [[ -n "$alt" && -d "$alt" ]]; then
        cwd_abs="$alt"
      else
        echo >&2 "❌ cwd does not exist or is not a directory: $cwd_abs"
        exit 1
      fi
    else
      echo >&2 "❌ cwd does not exist or is not a directory: $cwd_abs"
      exit 1
    fi
  fi

  local config_abs
  config_abs="$(resolve_path "$cwd_abs" "$config_input" "config")" || exit 1
  # Do not require file existence yet – let engine validate. But we already have absolute.

  # Resolve binary BEFORE cd to cwd so workspace lookups use runner workspace
  local bin
  bin="$(resolve_binary)" || exit 1
  echo "✅ using binary: $bin" >&2
  echo "📋 cwd: $cwd_abs" >&2
  echo "📋 config: $config_abs" >&2

  if command -v docker >/dev/null 2>&1; then
    echo "🐳 checking docker compose version..." >&2
    local compose_ver_raw=""
    compose_ver_raw="$(docker compose version 2>&1 | head -n 1 | tr -d '\r' | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' 2>/dev/null | cut -c1-500 || true)"
    if [[ -n "$compose_ver_raw" ]]; then
      echo "🐳 $compose_ver_raw" >&2
    else
      echo "⚠️ docker compose version returned empty" >&2
    fi
  else
    echo "⚠️ docker executable not found; engine preflight will report failure" >&2
  fi

  # Now cd to cwd for engine execution (engine expects cwd)
  cd "$cwd_abs"

  # Build engine invocation array
  local -a cmd
  cmd=("$bin" "--config" "$config_abs" "--cwd" "$cwd_abs")

  echo "🚀 ${bin} --config [REDACTED] --cwd [REDACTED]" >&2

  local engine_status=0
  "${cmd[@]}" || engine_status=$?

  # Locate manifest after engine run (engine writes even on failure)
  local manifest_path=""
  local evidence_dir=""
  manifest_path="$(find_manifest "$cwd_abs" 2>/dev/null || true)"
  if [[ -n "$manifest_path" && -f "$manifest_path" ]]; then
    # Ensure manifest_path is absolute
    if [[ "$manifest_path" != /* ]]; then
      manifest_path="$cwd_abs/$manifest_path"
    fi
    # Validate that manifest is inside cwd to prevent path escape
    # Use python to check containment
    local inside="true"
    if command -v python3 >/dev/null 2>&1; then
      inside="$(python3 -c 'import os,sys; cwd=os.path.realpath(sys.argv[1]); m=os.path.realpath(sys.argv[2]); print("true" if os.path.commonpath([cwd])==os.path.commonpath([cwd,m]) else "false")' "$cwd_abs" "$manifest_path" 2>/dev/null || echo "true")"
    fi
    if [[ "$inside" != "true" ]]; then
      echo >&2 "⚠️ manifest escapes cwd, ignoring: $manifest_path"
      manifest_path=""
      evidence_dir=""
    else
      evidence_dir="$(dirname "$manifest_path")"
      # Basic JSON validation without sourcing
      if command -v python3 >/dev/null 2>&1; then
        if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$manifest_path" 2>/dev/null; then
          echo >&2 "⚠️ result manifest is malformed JSON: $manifest_path"
          # Keep path but will treat outcome as failure
        fi
      elif command -v jq >/dev/null 2>&1; then
        if ! jq empty "$manifest_path" 2>/dev/null; then
          echo >&2 "⚠️ result manifest is malformed JSON: $manifest_path"
        fi
      fi
    fi
  else
    # No manifest found – keep empty, will infer from engine status
    manifest_path=""
    evidence_dir=""
  fi

  # Derive outputs from manifest or engine status
  local outcome="" failed_phase="" sanitized_outcome="" sanitized_phase=""
  if [[ -n "$manifest_path" && -f "$manifest_path" ]]; then
    outcome="$(parse_manifest_field "$manifest_path" "outcome" 2>/dev/null || true)"
    failed_phase="$(parse_manifest_field "$manifest_path" "phase" 2>/dev/null || true)"
    # Manifest uses phase for failed phase; if outcome success, phase is cleanup but we output empty failed-phase
    if [[ "$outcome" == "success" ]]; then
      failed_phase=""
    else
      # If outcome not success/failure, fallback to engine status
      if [[ "$outcome" != "success" && "$outcome" != "failure" ]]; then
        if [[ $engine_status -eq 0 ]]; then
          outcome="success"
          failed_phase=""
        else
          outcome="failure"
          # keep phase if present else fallback
          if [[ -z "$failed_phase" ]]; then
            failed_phase="unknown"
          fi
        fi
      fi
    fi
  else
    # No manifest – infer from engine status
    if [[ $engine_status -eq 0 ]]; then
      outcome="success"
      failed_phase=""
    else
      outcome="failure"
      failed_phase="unknown"
    fi
  fi

  sanitized_outcome="$(sanitize_for_output "$outcome")"
  sanitized_phase="$(sanitize_for_output "$failed_phase")"
  local sanitized_evidence_dir=""
  local sanitized_manifest=""
  if [[ -n "$evidence_dir" ]]; then
    sanitized_evidence_dir="$(sanitize_for_output "$evidence_dir")"
  fi
  if [[ -n "$manifest_path" ]]; then
    sanitized_manifest="$(sanitize_for_output "$manifest_path")"
  fi

  # Determine artifact-name output based on policy and outcome
  local artifact_output=""
  if [[ "$policy" == "never" ]]; then
    artifact_output=""
  elif [[ "$policy" == "always" ]]; then
    if [[ -n "$evidence_dir" && -d "$evidence_dir" ]]; then
      artifact_output="$artifact_name_input"
    else
      # No evidence dir yet, still advertise name? but only if engine created evidence.
      # Check if manifest exists implies evidence dir exists.
      if [[ -n "$manifest_path" ]]; then
        artifact_output="$artifact_name_input"
      else
        artifact_output=""
      fi
    fi
  else # failure
    if [[ "$sanitized_outcome" == "failure" ]]; then
      if [[ -n "$evidence_dir" && -d "$evidence_dir" ]]; then
        artifact_output="$artifact_name_input"
      elif [[ -n "$manifest_path" ]]; then
        artifact_output="$artifact_name_input"
      else
        # Still set artifact name if outcome failure, even if dir not found? Task says evidence upload is requested only after failure.
        # We set name so upload step can attempt and warn if no files.
        artifact_output="$artifact_name_input"
      fi
    else
      artifact_output=""
    fi
  fi
  artifact_output="$(sanitize_for_output "$artifact_output")"

  # Console summary for visibility in every step (engine also logs per-phase)
  {
    local summary_icon="✅"
    if [[ "$sanitized_outcome" == "failure" ]]; then summary_icon="❌"; fi
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::Compose sandbox summary" >&2; fi
    echo "${summary_icon} outcome=${sanitized_outcome} phase=${sanitized_phase:-none} engine_status=${engine_status}" >&2
    if [[ -n "$sanitized_evidence_dir" ]]; then echo "📁 evidence-directory=${sanitized_evidence_dir}" >&2; fi
    if [[ -n "$sanitized_manifest" ]]; then echo "📄 result-manifest=${sanitized_manifest}" >&2; fi
    if [[ -n "$manifest_path" && -f "$manifest_path" ]]; then
      local timings_line=""
      if command -v python3 >/dev/null 2>&1; then
        timings_line="$(python3 - "$manifest_path" <<'PY' 2>/dev/null || true
import json,sys
p=sys.argv[1]
try:
  d=json.load(open(p))
  t=d.get('timings',{})
  files=d.get('evidenceFiles',[])
  phase=d.get('phase','')
  outcome=d.get('outcome','')
  err=d.get('errors',{}).get('primary','')
  print(f"timings total={t.get('total',0)}ms validate={t.get('validate',0)}ms prepare={t.get('prepare',0)}ms preflight={t.get('preflight',0)}ms start={t.get('start',0)}ms readiness={t.get('readiness',0)}ms test={t.get('test',0)}ms evidence={t.get('evidence',0)}ms cleanup={t.get('cleanup',0)}ms | phase={phase} outcome={outcome} files={','.join(files)}")
  if err:
    print(f"primary error: {str(err)[:500]}")
except: pass
PY
)"
        if [[ -n "$timings_line" ]]; then
          echo "⏱ $timings_line" | head -n 5 >&2
        fi
      elif command -v jq >/dev/null 2>&1; then
        echo "⏱ $(jq -c '{phase,outcome,timings,evidenceFiles} // empty' "$manifest_path" 2>/dev/null | cut -c1-500)" >&2
      fi
      if [[ -n "$artifact_output" ]]; then
        echo "📦 artifact=${artifact_output} policy=${policy}" >&2
      else
        echo "📦 artifact: none (policy=${policy} outcome=${sanitized_outcome})" >&2
      fi
    else
      echo "⚠️ no manifest found at ${manifest_path:-<none>}" >&2
      if [[ -n "$artifact_output" ]]; then echo "📦 artifact=${artifact_output} (no manifest)" >&2; fi
    fi
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::" >&2; fi
  } || true

  # Write outputs to GITHUB_OUTPUT
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      printf "outcome=%s\n" "$sanitized_outcome"
      printf "failed-phase=%s\n" "$sanitized_phase"
      printf "evidence-directory=%s\n" "$sanitized_evidence_dir"
      printf "result-manifest=%s\n" "$sanitized_manifest"
      printf "artifact-name=%s\n" "$artifact_output"
    } >> "$GITHUB_OUTPUT"
  fi

  # Also persist manifest path for summarize step via temp file (in case outputs not yet propagated to next step's env derivation before always()?)
  # Write to runner temp for debugging; summarize.sh will prefer env COMPOSE_SANDBOX_RESULT_MANIFEST or fallback to finding.
  if [[ -n "${RUNNER_TEMP:-}" && -n "$manifest_path" ]]; then
    printf '%s' "$manifest_path" > "${RUNNER_TEMP}/compose-sandbox-manifest-path" 2>/dev/null || true
  fi

  # Preserve engine exit status
  if [[ $engine_status -ne 0 ]]; then
    exit $engine_status
  fi
}

main "$@"
