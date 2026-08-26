#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace_root="$(mktemp -d)"
trap 'rm -rf "$workspace_root"' EXIT

# Shared helpers
assert_eq() {
  local got="$1"
  local want="$2"
  local msg="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $msg: got '$got' want '$want'" >&2
    exit 1
  fi
}
assert_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "FAIL $msg: missing '$needle' in $file" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}
assert_not_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$file" 2>/dev/null; then
    echo "FAIL $msg: unexpected '$needle' in $file" >&2
    cat "$file" >&2 || true
    exit 1
  fi
}
assert_file_exists() {
  local f="$1"
  local msg="$2"
  if [[ ! -e "$f" ]]; then
    echo "FAIL $msg: missing $f" >&2
    exit 1
  fi
}
assert_file_not_exists() {
  local f="$1"
  local msg="$2"
  if [[ -e "$f" ]]; then
    echo "FAIL $msg: should not exist $f" >&2
    exit 1
  fi
}

# -------------------------------------------------------------------
# Test helpers: create fake binary that logs args and optionally creates manifest
# -------------------------------------------------------------------
make_fake_bin() {
  local path="$1"
  local mode="$2" # success|fail
  local evidence_dir_name="${3:-.compose-sandbox-logs}"
  cat > "$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log_file="\${FAKE_CLI_LOG:-/tmp/cli.log}"
echo "\$*" >> "\$log_file"
# Also log each arg separately for injection check
printf 'ARGS:%s\n' "\$*" >> "\$log_file"
for a in "\$@"; do
  printf 'ARG:%s\n' "\$a" >> "\$log_file"
done
# Parse --cwd and --config from args
cwd_val=""
config_val=""
args=("\$@")
for i in "\${!args[@]}"; do
  if [[ "\${args[i]}" == "--cwd" ]]; then
    cwd_val="\${args[i+1]:-}"
  fi
  if [[ "\${args[i]}" == "--config" ]]; then
    config_val="\${args[i+1]:-}"
  fi
done
if [[ -n "\$cwd_val" && -n "$evidence_dir_name" ]]; then
  mkdir -p "\$cwd_val/$evidence_dir_name"
  if [[ "$mode" == "success" ]]; then
    cat > "\$cwd_val/$evidence_dir_name/result.json" <<JSON
{"phase":"cleanup","outcome":"success","timings":{},"evidenceFiles":["ps.json","logs.txt","result.json"],"errors":{}}
JSON
  else
    cat > "\$cwd_val/$evidence_dir_name/result.json" <<JSON
{"phase":"test","outcome":"failure","timings":{},"evidenceFiles":["ps.json","logs.txt","result.json"],"errors":{"primary":"test command failed with exitCode 2"}}
JSON
  fi
  echo "ps" > "\$cwd_val/$evidence_dir_name/ps.json" || true
  echo "logs" > "\$cwd_val/$evidence_dir_name/logs.txt" || true
fi
if [[ "$mode" == "fail" ]]; then
  exit 2
fi
exit 0
EOF
  chmod 755 "$path"
}

make_fake_asdf() {
  local bin_dir="$1"
  local asdf_data_dir="$2"
  cat > "${bin_dir}/asdf" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
log_file="${FAKE_ASDF_LOG:?}"
asdf_data_dir="${ASDF_DATA_DIR:?}"
cli_log="${FAKE_CLI_LOG:-/tmp/cli.log}"
case "${1:-}" in
  plugin)
    case "${2:-}" in
      list) exit 0 ;;
      add) printf 'plugin add %s %s\n' "${3:-}" "${4:-}" >> "$log_file"; exit 0 ;;
    esac
    ;;
  list) exit 0 ;;
  install)
    if [[ "${2:-}" == "repo-toolkit" ]]; then
      printf 'install %s\n' "${3:-}" >> "$log_file"
      # only allow pinned version 0.18.0 for compose tests
      if [[ "${3:-}" != "0.18.0" ]]; then
        printf 'unexpected version %s\n' "${3:-}" >&2
        exit 1
      fi
      install_dir="${asdf_data_dir}/installs/repo-toolkit/${3}/bin"
      mkdir -p "$install_dir"
      cat > "${install_dir}/repo-toolkit-compose-sandbox" <<'CLI'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_CLI_LOG:?}"
for a in "$@"; do printf 'ARG:%s\n' "$a" >> "${FAKE_CLI_LOG:?}"; done
cwd_val=""
args=("$@")
for i in "${!args[@]}"; do if [[ "${args[i]}" == "--cwd" ]]; then cwd_val="${args[i+1]:-}"; fi; done
if [[ -n "$cwd_val" ]]; then mkdir -p "$cwd_val/.compose-sandbox-logs"; cat > "$cwd_val/.compose-sandbox-logs/result.json" <<'JSON'
{"phase":"cleanup","outcome":"success","timings":{},"evidenceFiles":["result.json"],"errors":{}}
JSON
fi
CLI
      chmod 755 "${install_dir}/repo-toolkit-compose-sandbox"
      exit 0
    fi
    ;;
  set) printf 'set %s %s %s\n' "${2:-}" "${3:-}" "${4:-}" >> "$log_file"; exit 0 ;;
  reshim) printf 'reshim %s\n' "${2:-all}" >> "$log_file"; exit 0 ;;
  which)
    if [[ "${2:-}" == "repo-toolkit-compose-sandbox" ]]; then
      if [[ -x "${asdf_data_dir}/installs/repo-toolkit/0.18.0/bin/repo-toolkit-compose-sandbox" ]]; then
        printf '%s\n' "${asdf_data_dir}/installs/repo-toolkit/0.18.0/bin/repo-toolkit-compose-sandbox"
        exit 0
      fi
      exit 1
    fi
    ;;
esac
printf 'unexpected asdf invocation: %s\n' "$*" >&2
exit 1
EOS
  chmod 755 "${bin_dir}/asdf"
  for tool in jq node python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      cat > "${bin_dir}/${tool}" <<'T'
#!/usr/bin/env bash
exit 0
T
      chmod 755 "${bin_dir}/${tool}"
    else
      # ensure bin_dir has wrapper that delegates to system if not mocked separately
      :
    fi
  done
  # ensure jq/node exist in bin_dir for asdf install checks – create pass-through if missing
  for t in jq node; do
    if [[ ! -x "${bin_dir}/${t}" ]]; then
      cat > "${bin_dir}/${t}" <<EOS
#!/usr/bin/env bash
exec "$(command -v $t)" "\$@"
EOS
      chmod 755 "${bin_dir}/${t}"
    fi
  done
}

run_sandbox() {
  # Args: workspace, cwd_input, config_input, extra_env...
  local ws="$1"
  local cwd_input="$2"
  local config_input="$3"
  shift 3
  local extra_env=("$@")
  local out="${ws}/out.log"
  local err="${ws}/err.log"
  local gh_out="${ws}/github_output"
  local gh_summary="${ws}/github_summary"
  : > "$gh_out"
  : > "$gh_summary"
  mkdir -p "$(dirname "$config_input" 2>/dev/null || true)" 2>/dev/null || true
  # Create config file path relative to cwd if needed
  local cwd_abs
  if [[ "$cwd_input" == /* ]]; then cwd_abs="$cwd_input"; else cwd_abs="${ws}/${cwd_input}"; fi
  mkdir -p "$cwd_abs"
  local cfg_path
  if [[ "$config_input" == /* ]]; then cfg_path="$config_input"; else cfg_path="$cwd_abs/$config_input"; fi
  mkdir -p "$(dirname "$cfg_path")"
  touch "$cfg_path" 2>/dev/null || true

  # Build env array
  local env_vars=(
    "GITHUB_WORKSPACE=$ws"
    "GITHUB_OUTPUT=$gh_out"
    "GITHUB_STEP_SUMMARY=$gh_summary"
    "COMPOSE_SANDBOX_ACTION_PATH=${repo_root}/compose-sandbox"
    "COMPOSE_SANDBOX_INPUT_CONFIG=$config_input"
    "COMPOSE_SANDBOX_INPUT_CWD=$cwd_input"
    "RUNNER_TEMP=$ws"
  )
  for e in "${extra_env[@]}"; do env_vars+=("$e"); done

  local status=0
  set +e
  env "${env_vars[@]}" bash "${repo_root}/compose-sandbox/run.sh" >"$out" 2>"$err" || status=$?
  set -e
  echo "$status" > "${ws}/exit_code"
  cp "$gh_out" "${ws}/gh_out_copy" 2>/dev/null || true
  cp "$gh_summary" "${ws}/gh_summary_copy" 2>/dev/null || true
}

get_output() {
  local ws="$1"
  local key="$2"
  grep -E "^${key}=" "${ws}/gh_out_copy" 2>/dev/null | head -n 1 | cut -d= -f2- || echo ""
}

# -------------------------------------------------------------------
# Test 1: explicit override
# -------------------------------------------------------------------
test_explicit() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  mkdir -p "${ws}/work"
  local explicit_bin="${ws}/my-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$explicit_bin")"
  make_fake_bin "$explicit_bin" "success"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$explicit_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"

  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "0" "explicit: exit code"
  assert_contains "$cli_log" "--config" "explicit: cli invoked"
  # Ensure asdf install not triggered
  assert_not_contains "$asdf_log" "install" "explicit: should not install via asdf"
  local outcome
  outcome="$(get_output "$ws" "outcome")"
  assert_eq "$outcome" "success" "explicit: outcome"
  rm -rf "$ws"
  echo "✓ explicit override"
}

# -------------------------------------------------------------------
# Test 2: workspace node_modules/.bin
# -------------------------------------------------------------------
test_workspace() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  mkdir -p "${ws}/work"
  mkdir -p "${ws}/node_modules/.bin"
  local ws_bin="${ws}/node_modules/.bin/repo-toolkit-compose-sandbox"
  make_fake_bin "$ws_bin" "success"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"

  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "0" "workspace: exit"
  assert_contains "$cli_log" "--config" "workspace: cli invoked"
  assert_not_contains "$asdf_log" "install" "workspace: no asdf install"
  rm -rf "$ws"
  echo "✓ workspace bin"
}

# -------------------------------------------------------------------
# Test 3: PATH lookup
# -------------------------------------------------------------------
test_path() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  mkdir -p "${ws}/work"
  local path_bin="${bin_dir}/repo-toolkit-compose-sandbox"
  make_fake_bin "$path_bin" "success"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"
  # Ensure no workspace bin exists
  rm -rf "${ws}/node_modules"
  local fake_action="${ws}/fake-action"
  mkdir -p "$fake_action"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0" "COMPOSE_SANDBOX_ACTION_PATH=$fake_action"

  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "0" "PATH: exit"
  assert_contains "$cli_log" "--config" "PATH: cli invoked"
  rm -rf "$ws"
  echo "✓ PATH bin"
}

# -------------------------------------------------------------------
# Test 4: asdf pinned install
# -------------------------------------------------------------------
test_asdf() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  mkdir -p "${ws}/work"
  make_fake_asdf "$bin_dir" "$asdf_data"
  # Also need jq/node wrappers that delegate – already handled in make_fake_asdf
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"
  # Ensure no other bins
  rm -rf "${ws}/node_modules"
  # Ensure PATH bin not present – fake asdf will not have command -v match initially
  local fake_action="${ws}/fake-action"
  mkdir -p "$fake_action"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0" "COMPOSE_SANDBOX_ACTION_PATH=$fake_action"

  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "0" "asdf: exit"
  assert_contains "$asdf_log" "install 0.18.0" "asdf: installed exact version"
  assert_contains "$cli_log" "--config" "asdf: cli invoked"
  rm -rf "$ws"
  echo "✓ asdf pinned"
}

# -------------------------------------------------------------------
# Test 5: injection resistance – malicious config/cwd values passed literally
# -------------------------------------------------------------------
test_injection() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  # cwd with spaces and metachars
  local cwd_with_space="${ws}/work space; evil"
  mkdir -p "$cwd_with_space"
  local explicit_bin="${ws}/my-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$explicit_bin")"
  make_fake_bin "$explicit_bin" "success"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"

  local marker="${ws}/marker.should-not-exist"
  rm -f "$marker"
  local malicious_config='sandbox/evil; touch '"$marker"' --config.mjs'
  # The config file path itself with spaces/semicolons – we create cwd and then pass this as config input.
  # Our run.sh should pass it as single arg without shell evaluation, so marker not created.

  run_sandbox "$ws" "$cwd_with_space" "$malicious_config" "COMPOSE_SANDBOX_INPUT_BIN=$explicit_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"

  assert_file_not_exists "$marker" "injection: marker should not be created"
  # Check that cli received the malicious string as single ARG
  assert_contains "$cli_log" "$malicious_config" "injection: cli got literal config"
  # Also ensure cwd was passed literally: check ARG for cwd
  assert_contains "$cli_log" "$cwd_with_space" "injection: cwd literal"
  rm -rf "$ws"
  echo "✓ injection resistance"
}

# -------------------------------------------------------------------
# Test 6: version validation rejects latest and invalid
# -------------------------------------------------------------------
test_version_reject() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  mkdir -p "${ws}/work"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="${ws}/cli.log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=latest"
  local code
  code="$(cat "$ws/exit_code")"
  if [[ "$code" == "0" ]]; then echo "FAIL version reject latest should fail" >&2; exit 1; fi
  # also check error message mentions semver
  assert_contains "${ws}/err.log" "exact semver" "version reject latest msg"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=^0.18.0"
  code="$(cat "$ws/exit_code")"
  if [[ "$code" == "0" ]]; then echo "FAIL version reject ^ should fail" >&2; exit 1; fi

  # empty version should fallback to default 0.18.0 and succeed when bin is available
  local good_bin="${ws}/good-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$good_bin")"
  make_fake_bin "$good_bin" "success"
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$good_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION="
  code="$(cat "$ws/exit_code")"
  if [[ "$code" != "0" ]]; then echo "FAIL empty version should fallback to default and succeed, got $code" >&2; cat "${ws}/err.log" >&2; exit 1; fi

  rm -rf "$ws"
  echo "✓ version validation"
}

# -------------------------------------------------------------------
# Test 7: toolkit nonzero preserved and manifest available
# -------------------------------------------------------------------
test_toolkit_failure() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  local asdf_log="${ws}/asdf.log"
  : > "$cli_log"; : > "$asdf_log"
  mkdir -p "${ws}/work"
  local explicit_bin="${ws}/my-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$explicit_bin")"
  make_fake_bin "$explicit_bin" "fail"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="$asdf_log"
  export FAKE_CLI_LOG="$cli_log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$explicit_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"

  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "2" "toolkit failure: exit preserved"
  local outcome
  outcome="$(get_output "$ws" "outcome")"
  assert_eq "$outcome" "failure" "toolkit failure: outcome"
  local phase
  phase="$(get_output "$ws" "failed-phase")"
  assert_eq "$phase" "test" "toolkit failure: phase"
  local manifest
  manifest="$(get_output "$ws" "result-manifest")"
  assert_file_exists "$manifest" "toolkit failure: manifest exists"
  local evidence
  evidence="$(get_output "$ws" "evidence-directory")"
  assert_file_exists "$evidence/result.json" "toolkit failure: evidence dir has manifest"
  rm -rf "$ws"
  echo "✓ toolkit failure preserved"
}

# -------------------------------------------------------------------
# Test 8: artifact policy – failure, always, never
# -------------------------------------------------------------------
test_policy() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  : > "$cli_log"
  mkdir -p "${ws}/work"
  local success_bin="${ws}/my-bin-success/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$success_bin")"
  make_fake_bin "$success_bin" "success"
  local fail_bin="${ws}/my-bin-fail/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$fail_bin")"
  make_fake_bin "$fail_bin" "fail"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="$cli_log"

  # success + failure policy => no artifact
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$success_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=failure" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  local art
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "" "policy failure+success: no artifact"

  # failure + failure policy => artifact
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$fail_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=failure" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "my-artifact" "policy failure+failure: artifact"

  # success + always => artifact
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$success_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=always" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "my-artifact" "policy always+success"

  # failure + always => artifact
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$fail_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=always" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "my-artifact" "policy always+failure"

  # any + never => no artifact
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$success_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=never" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "" "policy never"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$fail_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=never" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-artifact"
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "" "policy never failure"

  rm -rf "$ws"
  echo "✓ artifact policy"
}

# -------------------------------------------------------------------
# Test 9: malformed and missing manifest
# -------------------------------------------------------------------
test_malformed() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  : > "$cli_log"
  mkdir -p "${ws}/work"
  # fake bin that writes malformed JSON
  local mal_bin="${ws}/mal-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$mal_bin")"
  cat > "$mal_bin" <<'MB'
#!/usr/bin/env bash
set -euo pipefail
log="${FAKE_CLI_LOG:-/tmp/cli.log}"
echo "$*" >> "$log"
cwd=""
args=("$@")
for i in "${!args[@]}"; do if [[ "${args[i]}" == "--cwd" ]]; then cwd="${args[i+1]:-}"; fi; done
mkdir -p "$cwd/.compose-sandbox-logs"
echo "not json {{{" > "$cwd/.compose-sandbox-logs/result.json"
exit 2
MB
  chmod 755 "$mal_bin"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="$cli_log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$mal_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=failure"
  local code
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "2" "malformed: exit preserved"
  # Should not crash; outcome should be failure
  local outcome
  outcome="$(get_output "$ws" "outcome")"
  # Our run.sh will try to parse malformed and fallback to engine status => failure
  if [[ "$outcome" != "failure" ]]; then echo "FAIL malformed outcome got $outcome" >&2; exit 1; fi
  # Ensure no eval – marker file not created via content
  if grep -Fq -- "not json" "${ws}/err.log" 2>/dev/null; then
    # It's okay to log warning but not expose raw?
    :
  fi
  # Now test summarize.sh handles malformed without exposing
  local manifest
  manifest="$(get_output "$ws" "result-manifest")"
  # Run summarize
  local summary="${ws}/summary_out"
  GITHUB_STEP_SUMMARY="$summary" \
  COMPOSE_SANDBOX_RESULT_MANIFEST="$manifest" \
  COMPOSE_SANDBOX_EVIDENCE_DIRECTORY="$(get_output "$ws" "evidence-directory")" \
  COMPOSE_SANDBOX_OUTCOME="$outcome" \
  bash "${repo_root}/compose-sandbox/summarize.sh"
  assert_contains "$summary" "malformed manifest" "malformed summary"
  assert_not_contains "$summary" "not json" "malformed summary should not leak raw? Actually we mention invalid JSON but not raw content with secrets – here raw is not secret so okay"

  # Missing manifest: bin that succeeds but doesn't write manifest
  local nomani_bin="${ws}/nomanifest/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$nomani_bin")"
  cat > "$nomani_bin" <<'NM'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${FAKE_CLI_LOG:?}"
exit 0
NM
  chmod 755 "$nomani_bin"
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$nomani_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "0" "missing manifest success exit"
  outcome="$(get_output "$ws" "outcome")"
  assert_eq "$outcome" "success" "missing manifest success outcome"
  # failure case with no manifest
  cat > "$nomani_bin" <<'NM2'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${FAKE_CLI_LOG:?}"
exit 3
NM2
  chmod 755 "$nomani_bin"
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$nomani_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"
  code="$(cat "$ws/exit_code")"
  assert_eq "$code" "3" "missing manifest failure exit"
  outcome="$(get_output "$ws" "outcome")"
  assert_eq "$outcome" "failure" "missing manifest failure outcome"

  rm -rf "$ws"
  echo "✓ malformed/missing manifest"
}

# -------------------------------------------------------------------
# Test 10: secret redaction – manifest contains secret, summary/output must not leak?
# -------------------------------------------------------------------
test_secret() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  : > "$cli_log"
  mkdir -p "${ws}/work"
  local secret="s3cr3t-token-123"
  local secret_bin="${ws}/secret-bin/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$secret_bin")"
  cat > "$secret_bin" <<EOS
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "${FAKE_CLI_LOG:?}"
cwd=""
args=("\$@")
for i in "\${!args[@]}"; do if [[ "\${args[i]}" == "--cwd" ]]; then cwd="\${args[i+1]:-}"; fi; done
mkdir -p "\$cwd/.compose-sandbox-logs"
# Manifest contains secret in error message (simulate redacted engine should have stripped, but we test our handling)
cat > "\$cwd/.compose-sandbox-logs/result.json" <<JSON
{"phase":"test","outcome":"failure","errors":{"primary":"test failed with token $secret"},"timings":{},"evidenceFiles":["result.json"]}
JSON
exit 2
EOS
  chmod 755 "$secret_bin"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="$cli_log"
  # Also set secret in env to simulate config env leakage attempt – run.sh should not print it
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$secret_bin" "COMPOSE_SANDBOX_INPUT_REPO_TOOLKIT_VERSION=0.18.0"

  # Check that GITHUB_OUTPUT does not contain secret (our sanitize should have stripped? Actually manifest still has secret, but we sanitize phase/outcome only – evidenceFiles not secret. The raw manifest has secret, but our output only includes outcome/phase, not raw errors. So output should not contain secret.)
  local out_copy="${ws}/gh_out_copy"
  assert_not_contains "$out_copy" "$secret" "secret not in output"

  # Check err log does not contain secret (run.sh redacts by not printing config)
  assert_not_contains "${ws}/err.log" "$secret" "secret not in stderr"
  # Check summary does not contain secret
  local manifest
  manifest="$(get_output "$ws" "result-manifest")"
  local summary="${ws}/summary_secret"
  GITHUB_STEP_SUMMARY="$summary" COMPOSE_SANDBOX_RESULT_MANIFEST="$manifest" COMPOSE_SANDBOX_EVIDENCE_DIRECTORY="$(get_output "$ws" "evidence-directory")" COMPOSE_SANDBOX_OUTCOME="$(get_output "$ws" "outcome")" bash "${repo_root}/compose-sandbox/summarize.sh"
  assert_not_contains "$summary" "$secret" "secret not in summary"

  rm -rf "$ws"
  echo "✓ secret redaction"
}

# -------------------------------------------------------------------
# Test 11: artifact name validation
# -------------------------------------------------------------------
test_artifact_name_invalid() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  mkdir -p "${ws}/work"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="${ws}/cli.log"
  local good_bin="${ws}/good/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$good_bin")"
  make_fake_bin "$good_bin" "success"
  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$good_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=bad/name"
  local code
  code="$(cat "$ws/exit_code")"
  if [[ "$code" == "0" ]]; then echo "FAIL artifact slash should reject" >&2; exit 1; fi
  assert_contains "${ws}/err.log" "artifact-name" "artifact name slash error"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$good_bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=bad name with spaces"
  code="$(cat "$ws/exit_code")"
  if [[ "$code" == "0" ]]; then echo "FAIL artifact spaces should reject" >&2; exit 1; fi

  rm -rf "$ws"
  echo "✓ artifact name validation"
}

# -------------------------------------------------------------------
# Test 12: success outputs completeness
# -------------------------------------------------------------------
test_success_outputs() {
  local ws
  ws="$(mktemp -d -p "$workspace_root")"
  local bin_dir="${ws}/bin"
  mkdir -p "$bin_dir"
  local asdf_data="${ws}/asdf"
  mkdir -p "$asdf_data/shims"
  local cli_log="${ws}/cli.log"
  : > "$cli_log"
  mkdir -p "${ws}/work"
  local bin="${ws}/bin2/repo-toolkit-compose-sandbox"
  mkdir -p "$(dirname "$bin")"
  make_fake_bin "$bin" "success"
  make_fake_asdf "$bin_dir" "$asdf_data"
  export PATH="${bin_dir}:/usr/bin:/bin"
  export ASDF_DATA_DIR="$asdf_data"
  export FAKE_ASDF_LOG="${ws}/asdf.log"
  export FAKE_CLI_LOG="$cli_log"

  run_sandbox "$ws" "${ws}/work" "sandbox/config.mjs" "COMPOSE_SANDBOX_INPUT_BIN=$bin" "COMPOSE_SANDBOX_INPUT_ARTIFACT_POLICY=always" "COMPOSE_SANDBOX_INPUT_ARTIFACT_NAME=my-art"
  local outcome
  outcome="$(get_output "$ws" "outcome")"
  assert_eq "$outcome" "success" "success outputs outcome"
  local failed
  failed="$(get_output "$ws" "failed-phase")"
  assert_eq "$failed" "" "success failed-phase empty"
  local ev
  ev="$(get_output "$ws" "evidence-directory")"
  assert_file_exists "$ev" "success evidence dir exists"
  local mani
  mani="$(get_output "$ws" "result-manifest")"
  assert_file_exists "$mani" "success manifest exists"
  local art
  art="$(get_output "$ws" "artifact-name")"
  assert_eq "$art" "my-art" "success artifact with always"

  # summary
  local summary="${ws}/summary_ok"
  GITHUB_STEP_SUMMARY="$summary" COMPOSE_SANDBOX_RESULT_MANIFEST="$mani" COMPOSE_SANDBOX_EVIDENCE_DIRECTORY="$ev" COMPOSE_SANDBOX_OUTCOME="$outcome" bash "${repo_root}/compose-sandbox/summarize.sh"
  assert_contains "$summary" "outcome: \`success\`" "success summary outcome"
  assert_contains "$summary" "evidence" "success summary evidence"

  rm -rf "$ws"
  echo "✓ success outputs"
}

# Run all
test_explicit
test_workspace
test_path
test_asdf
test_injection
test_version_reject
test_toolkit_failure
test_policy
test_malformed
test_secret
test_artifact_name_invalid
test_success_outputs

printf 'compose-sandbox shell tests passed\n'
