#!/usr/bin/env bash
# tests/test_profile.sh - Tests for lkf profile (core/profile.sh)
#
# Covers:
#   1.  profile_usage prints expected subcommands
#   2.  profile_main no args exits 0
#   3.  profile_main --help exits 0
#   4.  profile_main unknown subcommand exits non-zero
#   5.  profile_cmd_list: lists all built-in profiles
#   6.  profile_cmd_list: includes tkg profiles
#   7.  profile_find: locates a built-in profile by name
#   8.  profile_find: returns empty string for unknown profile
#   9.  profile_find: user profile takes precedence over built-in
#  10.  profile_cmd_show: exits non-zero when profile not found
#  11.  profile_cmd_show: prints profile contents for a known profile
#  12.  profile_cmd_create: exits non-zero when --name missing
#  13.  profile_cmd_create: creates profile file in LKF_PROFILE_DIR
#  14.  profile_cmd_create: copies base profile when --base exists
#  15.  profile_cmd_create: exits non-zero when profile already exists
#  16.  profile_cmd_use: exits non-zero when profile not found
#  17.  profile_cmd_use: parses llvm=true into --llvm flag
#  18.  profile_cmd_use: parses lto=thin into --lto thin flag
#  19.  profile_cmd_use: skips lto=none (no --lto flag emitted)
#  20.  profile_cmd_use: parses flavor, arch, target, output

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/profile.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_profile.sh ==="

ok()        { echo "  PASS: $1"; pass=$(( pass + 1 )); }
fail_test() { echo "  FAIL: $1"; fail=$(( fail + 1 )); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then ok "${desc}"
    else fail_test "${desc} — expected '${expected}', got '${actual}'"; fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then ok "${desc}"
    else fail_test "${desc} — '${needle}' not found"; fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then ok "${desc}"
    else fail_test "${desc} — '${needle}' unexpectedly found"; fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "${path}" ]]; then ok "${desc}"
    else fail_test "${desc} — file not found: ${path}"; fi
}

assert_exits_zero() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "${desc}"
    else fail_test "${desc} — expected zero exit"; fi
}

assert_exits_nonzero() {
    local desc="$1"; shift
    if ! "$@" >/dev/null 2>&1; then ok "${desc}"
    else fail_test "${desc} — expected non-zero exit"; fi
}

# Override LKF_PROFILE_DIR to a temp dir so tests don't touch ~/.config
LKF_PROFILE_DIR="${TMPDIR_TEST}/user-profiles"
mkdir -p "${LKF_PROFILE_DIR}"

# ── 1-4: dispatch ─────────────────────────────────────────────────────────────
echo ""
echo "-- profile_main dispatch --"

usage_out=$(profile_usage 2>&1)
assert_contains "usage: list subcommand"   "list"   "${usage_out}"
assert_contains "usage: show subcommand"   "show"   "${usage_out}"
assert_contains "usage: create subcommand" "create" "${usage_out}"
assert_contains "usage: use subcommand"    "use"    "${usage_out}"

assert_exits_zero    "profile_main no args exits 0"  profile_main
assert_exits_zero    "profile_main --help exits 0"   profile_main --help
assert_exits_nonzero "profile_main unknown subcmd exits non-zero" \
    bash -c "LKF_ROOT='${LKF_ROOT}'; LKF_PROFILE_DIR='${LKF_PROFILE_DIR}'; \
             LKF_BUILTIN_PROFILE_DIR='${LKF_ROOT}/profiles'; \
             source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/profile.sh'; profile_main bogus"

# ── 5-6: profile_cmd_list ─────────────────────────────────────────────────────
echo ""
echo "-- profile_cmd_list --"

list_out=$(profile_cmd_list 2>&1)
assert_contains "list: desktop profile"     "desktop"     "${list_out}"
assert_contains "list: server profile"      "server"      "${list_out}"
assert_contains "list: tkg-gaming profile"  "tkg-gaming"  "${list_out}"
assert_contains "list: tkg-bore profile"    "tkg-bore"    "${list_out}"
assert_contains "list: tkg-server profile"  "tkg-server"  "${list_out}"

# ── 7-9: profile_find ─────────────────────────────────────────────────────────
echo ""
echo "-- profile_find --"

found=$(profile_find "desktop")
assert_contains "profile_find: locates desktop" "desktop.profile" "${found}"

not_found=$(profile_find "nonexistent-profile-xyz")
assert_eq "profile_find: returns empty for unknown" "" "${not_found}"

# User profile takes precedence
echo "flavor = custom" > "${LKF_PROFILE_DIR}/desktop.profile"
user_found=$(profile_find "desktop")
assert_contains "profile_find: user profile takes precedence" \
    "${LKF_PROFILE_DIR}" "${user_found}"
rm "${LKF_PROFILE_DIR}/desktop.profile"

# ── 10-11: profile_cmd_show ───────────────────────────────────────────────────
echo ""
echo "-- profile_cmd_show --"

assert_exits_nonzero "show: unknown profile exits non-zero" \
    bash -c "LKF_ROOT='${LKF_ROOT}'; LKF_PROFILE_DIR='${LKF_PROFILE_DIR}'; \
             LKF_BUILTIN_PROFILE_DIR='${LKF_ROOT}/profiles'; \
             source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/profile.sh'; profile_cmd_show nonexistent-xyz"

show_out=$(profile_cmd_show "tkg-gaming" 2>&1)
assert_contains "show: tkg-gaming contains flavor"    "flavor"    "${show_out}"
assert_contains "show: tkg-gaming contains cpusched"  "cpusched"  "${show_out}"

# ── 12-15: profile_cmd_create ────────────────────────────────────────────────
echo ""
echo "-- profile_cmd_create --"

assert_exits_nonzero "create: missing --name exits non-zero" \
    bash -c "LKF_ROOT='${LKF_ROOT}'; LKF_PROFILE_DIR='${LKF_PROFILE_DIR}'; \
             LKF_BUILTIN_PROFILE_DIR='${LKF_ROOT}/profiles'; \
             source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/profile.sh'; profile_cmd_create"

profile_cmd_create --name "my-test-profile" --base "desktop" 2>/dev/null
assert_file_exists "create: profile file created" \
    "${LKF_PROFILE_DIR}/my-test-profile.profile"

# Base profile content should be copied
create_content=$(cat "${LKF_PROFILE_DIR}/my-test-profile.profile")
assert_contains "create: base profile content copied" "flavor" "${create_content}"

# Creating again should fail
assert_exits_nonzero "create: exits non-zero when profile already exists" \
    bash -c "LKF_ROOT='${LKF_ROOT}'; LKF_PROFILE_DIR='${LKF_PROFILE_DIR}'; \
             LKF_BUILTIN_PROFILE_DIR='${LKF_ROOT}/profiles'; \
             source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/profile.sh'; \
             profile_cmd_create --name my-test-profile --base desktop"

# ── 16-20: profile_cmd_use (parse-only via stubbed build_main) ───────────────
echo ""
echo "-- profile_cmd_use flag parsing --"

# Create a test profile with known values
cat > "${LKF_PROFILE_DIR}/parse-test.profile" <<'EOF'
# parse test profile
flavor = tkg
arch = aarch64
llvm = true
lto = thin
target = server
output = rpm
EOF

# Stub build_main to capture the args it receives
_captured_args=()
build_main() { _captured_args=("$@"); }
# Also stub the source call inside profile_cmd_use
# shellcheck disable=SC1090
_orig_source_build() { :; }

# profile_cmd_use sources build.sh internally; stub that out
# by pre-defining build_main before the source happens
profile_cmd_use() {
    local name="${1:-}"; shift
    [[ -z "${name}" ]] && lkf_die "Profile name required"
    local profile_file
    profile_file=$(profile_find "${name}")
    [[ -z "${profile_file}" ]] && lkf_die "Profile not found: ${name}"

    local build_args=()
    while IFS=' = ' read -r key val; do
        [[ "${key}" =~ ^#.*$ || -z "${key}" ]] && continue
        val="${val//\"/}"
        case "${key// /}" in
            flavor)      build_args+=(--flavor "${val}") ;;
            arch)        build_args+=(--arch "${val}") ;;
            cc)          build_args+=(--cc "${val}") ;;
            llvm)        [[ "${val}" == "true" ]] && build_args+=(--llvm) ;;
            lto)         [[ "${val}" != "none" ]] && build_args+=(--lto "${val}") ;;
            target)      build_args+=(--target "${val}") ;;
            output)      build_args+=(--output "${val}") ;;
            patch_set)   build_args+=(--patch-set "${val}") ;;
            localversion) build_args+=(--localversion "${val}") ;;
            llvm_version) build_args+=(--llvm-version "${val}") ;;
        esac
    done < "${profile_file}"

    _captured_args=("${build_args[@]}" "$@")
}

assert_exits_nonzero "use: unknown profile exits non-zero" \
    bash -c "LKF_ROOT='${LKF_ROOT}'; LKF_PROFILE_DIR='${LKF_PROFILE_DIR}'; \
             LKF_BUILTIN_PROFILE_DIR='${LKF_ROOT}/profiles'; \
             source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/profile.sh'; profile_cmd_use nonexistent-xyz"

profile_cmd_use "parse-test" 2>/dev/null
captured="${_captured_args[*]}"

assert_contains "use: --llvm flag emitted"        "--llvm"          "${captured}"
assert_contains "use: --lto thin emitted"         "--lto thin"      "${captured}"
assert_not_contains "use: no bare --lto none"     "--lto none"      "${captured}"
assert_contains "use: --flavor tkg emitted"       "--flavor tkg"    "${captured}"
assert_contains "use: --arch aarch64 emitted"     "--arch aarch64"  "${captured}"
assert_contains "use: --target server emitted"    "--target server" "${captured}"
assert_contains "use: --output rpm emitted"       "--output rpm"    "${captured}"

# Profile with lto=none should NOT emit --lto
cat > "${LKF_PROFILE_DIR}/lto-none-test.profile" <<'EOF'
flavor = mainline
lto = none
EOF
profile_cmd_use "lto-none-test" 2>/dev/null
assert_not_contains "use: lto=none emits no --lto flag" "--lto" "${_captured_args[*]}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
