#!/usr/bin/env bash
set -euo pipefail

# Append redacted summary from engine result manifest.
# Env vars are passed from action.yml; manifest is JSON validated without sourcing.

manifest_from_env="${COMPOSE_SANDBOX_RESULT_MANIFEST:-}"
manifest_from_input="${COMPOSE_SANDBOX_INPUT_RESULT_MANIFEST:-}"
evidence_dir_env="${COMPOSE_SANDBOX_EVIDENCE_DIRECTORY:-${COMPOSE_SANDBOX_INPUT_EVIDENCE_DIRECTORY:-}}"
outcome_env="${COMPOSE_SANDBOX_OUTCOME:-}"
failed_phase_env="${COMPOSE_SANDBOX_FAILED_PHASE:-}"
artifact_name_env="${COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME:-}"

manifest=""
if [[ -n "$manifest_from_env" && -f "$manifest_from_env" ]]; then
  manifest="$manifest_from_env"
elif [[ -n "$manifest_from_input" && -f "$manifest_from_input" ]]; then
  manifest="$manifest_from_input"
elif [[ -n "${RUNNER_TEMP:-}" && -f "${RUNNER_TEMP}/compose-sandbox-manifest-path" ]]; then
  candidate="$(cat "${RUNNER_TEMP}/compose-sandbox-manifest-path" 2>/dev/null || true)"
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    manifest="$candidate"
  fi
fi

# Fallback: try to locate via evidence dir
if [[ -z "$manifest" && -n "$evidence_dir_env" && -f "$evidence_dir_env/result.json" ]]; then
  manifest="$evidence_dir_env/result.json"
fi
if [[ -z "$manifest" && -n "${COMPOSE_SANDBOX_ACTION_PATH:-}" ]]; then
  # No manifest – we still write a minimal summary from env outputs if available
  :
fi

summary_file="${GITHUB_STEP_SUMMARY:-/dev/null}"

# Helper to safely parse JSON field via python3
parse_field() {
  local path="$1"
  local field="$2"
  if [[ ! -f "$path" ]]; then echo ""; return 0; fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" "$field" <<'PY' 2>/dev/null || echo ""
import json,sys
p=sys.argv[1]; f=sys.argv[2]
try:
  d=json.load(open(p))
  v=d.get(f,"")
  if isinstance(v,str): print(v)
  elif v is None: print("")
  else: print(str(v) if not isinstance(v,(dict,list)) else "")
except: print("")
PY
  else
    echo ""
  fi
}

sanitize() {
  local v="$1"
  v="$(printf '%s' "$v" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' 2>/dev/null || printf '%s' "$v")"
  v="${v//$'\n'/ }"
  v="${v//$'\r'/ }"
  if [[ ${#v} -gt 500 ]]; then v="${v:0:500}"; fi
  printf '%s' "$v"
}

outcome=""
phase=""
evidence_dir=""
manifest_path=""

if [[ -n "$manifest" && -f "$manifest" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$manifest" 2>/dev/null; then
      # malformed
      {
        echo "### Compose sandbox result"
        echo "- outcome: unknown (malformed manifest)"
        echo "- manifest: \`$(sanitize "$manifest")\` (invalid JSON)"
        if [[ -n "$evidence_dir_env" ]]; then echo "- evidence: \`$(sanitize "$evidence_dir_env")\`"; fi
        if [[ -n "$artifact_name_env" ]]; then echo "- artifact: \`$(sanitize "$artifact_name_env")\` (upload policy may apply)"; fi
        echo "- note: manifest is not valid JSON and was not evaluated as shell"
      } >> "$summary_file"
      exit 0
    fi
  fi
  outcome="$(parse_field "$manifest" "outcome")"
  phase="$(parse_field "$manifest" "phase")"
  # outcome already sanitized via parse, but sanitize again
  outcome="$(sanitize "$outcome")"
  phase="$(sanitize "$phase")"
  if [[ "$outcome" == "success" ]]; then
    phase=""
  fi
  evidence_dir="$(dirname "$manifest")"
  manifest_path="$manifest"
else
  # No manifest – use env outputs if available
  outcome="$(sanitize "$outcome_env")"
  phase="$(sanitize "$failed_phase_env")"
  evidence_dir="$(sanitize "$evidence_dir_env")"
  manifest_path=""
  if [[ -z "$outcome" ]]; then
    outcome="unknown"
  fi
fi

# Never include raw config or env values
# Summary contains only outcome, failed phase, artifact/evidence refs

{
  echo "### Compose sandbox result"
  echo "- outcome: \`$(sanitize "${outcome:-unknown}")\`"
  if [[ -n "$phase" ]]; then
    echo "- failed phase: \`$(sanitize "$phase")\`"
  else
    if [[ "$outcome" == "failure" ]]; then
      echo "- failed phase: \`unknown\`"
    else
      echo "- failed phase: \`\`"
    fi
  fi
  if [[ -n "$manifest_path" ]]; then
    echo "- evidence: \`$(sanitize "$manifest_path")\`"
    if [[ -n "$evidence_dir" && "$evidence_dir" != "$manifest_path" ]]; then
      echo "- evidence directory: \`$(sanitize "$evidence_dir")\`"
    fi
  elif [[ -n "$evidence_dir" ]]; then
    echo "- evidence directory: \`$(sanitize "$evidence_dir")\`"
  else
    echo "- evidence directory: \`\`"
  fi
  if [[ -n "$artifact_name_env" ]]; then
    # Only mention artifact name if it would be uploaded under current policy; but we mention configured name without implying upload occurred
    echo "- artifact: \`$(sanitize "$artifact_name_env")\`"
  fi
} >> "$summary_file"
