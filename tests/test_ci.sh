#!/usr/bin/env bash
# tests/test_ci.sh - Tests for lkf ci (ci/ci.sh)
#
# Covers:
#   1.  ci_usage prints expected options
#   2.  ci_main --help exits 0
#   3.  ci_main unknown option exits non-zero
#   4.  ci_main unknown --provider exits non-zero
#   5.  ci_generate_github: creates output file
#   6.  ci_generate_github: output contains 'jobs:'
#   7.  ci_generate_github: output contains 'runs-on:'
#   8.  ci_generate_github: output contains 'workflow_dispatch'
#   9.  ci_generate_github: --llvm adds LLVM install step
#  10.  ci_generate_github: --lto thin appears in build flags
#  11.  ci_generate_github: --release adds release job
#  12.  ci_generate_github: --matrix generates matrix strategy
#  13.  ci_generate_github: aarch64 adds cross-compiler install
#  14.  ci_generate_gitlab: creates output file
#  15.  ci_generate_gitlab: output contains 'stages:'
#  16.  ci_generate_gitlab: output contains 'script:'
#  17.  ci_generate_gitlab: --release adds release stage
#  18.  ci_generate_forgejo: creates output file
#  19.  ci_generate_forgejo: output contains 'on:'
#  20.  ci_generate_forgejo: output contains 'workflow_dispatch'
#  21.  ci_generate_forgejo: --release adds release job
#  22.  ci_main --provider github routes to ci_generate_github
#  23.  ci_main --provider gitlab routes to ci_generate_gitlab
#  24.  ci_main --provider forgejo routes to ci_generate_forgejo
#  25.  generated GitHub YAML: flavor appears in build command

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/ci/ci.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_ci.sh ==="

ok()        { echo "  PASS: $1"; pass=$(( pass + 1 )); }
fail_test() { echo "  FAIL: $1"; fail=$(( fail + 1 )); }

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

# ── 1-4: dispatch ─────────────────────────────────────────────────────────────
echo ""
echo "-- ci_main dispatch --"

usage_out=$(ci_usage 2>&1)
assert_contains "usage: --provider option"  "--provider" "${usage_out}"
assert_contains "usage: --arch option"      "--arch"     "${usage_out}"
assert_contains "usage: --llvm option"      "--llvm"     "${usage_out}"
assert_contains "usage: --release option"   "--release"  "${usage_out}"
assert_contains "usage: --matrix option"    "--matrix"   "${usage_out}"

assert_exits_zero    "ci_main --help exits 0" ci_main --help

assert_exits_nonzero "ci_main unknown option exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/ci/ci.sh'; ci_main --bogus"

assert_exits_nonzero "ci_main unknown --provider exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/ci/ci.sh'; ci_main --provider bitbucket"

# ── 5-13: ci_generate_github ─────────────────────────────────────────────────
echo ""
echo "-- ci_generate_github --"

GH_OUT="${TMPDIR_TEST}/github.yml"
ci_generate_github "x86_64" "mainline" "0" "none" "${GH_OUT}" "0" "0" 2>/dev/null
assert_file_exists "github: output file created" "${GH_OUT}"

gh_content=$(cat "${GH_OUT}")
assert_contains "github: has 'jobs:'"             "jobs:"             "${gh_content}"
assert_contains "github: has 'runs-on:'"          "runs-on:"          "${gh_content}"
assert_contains "github: has 'workflow_dispatch'" "workflow_dispatch" "${gh_content}"

# --llvm adds LLVM install step
GH_LLVM="${TMPDIR_TEST}/github-llvm.yml"
ci_generate_github "x86_64" "mainline" "1" "none" "${GH_LLVM}" "0" "0" 2>/dev/null
gh_llvm=$(cat "${GH_LLVM}")
assert_contains "github --llvm: LLVM install step" "llvm.sh" "${gh_llvm}"
assert_contains "github --llvm: --llvm in build cmd" "--llvm" "${gh_llvm}"

# --lto thin
GH_LTO="${TMPDIR_TEST}/github-lto.yml"
ci_generate_github "x86_64" "mainline" "0" "thin" "${GH_LTO}" "0" "0" 2>/dev/null
assert_contains "github --lto thin: appears in build flags" "--lto thin" "$(cat "${GH_LTO}")"

# --release adds release job
GH_REL="${TMPDIR_TEST}/github-release.yml"
ci_generate_github "x86_64" "mainline" "0" "none" "${GH_REL}" "1" "0" 2>/dev/null
assert_contains "github --release: release job present" "Create Release" "$(cat "${GH_REL}")"

# --matrix generates matrix strategy
GH_MAT="${TMPDIR_TEST}/github-matrix.yml"
ci_generate_github "x86_64,aarch64" "mainline" "0" "none" "${GH_MAT}" "0" "1" 2>/dev/null
assert_contains "github --matrix: strategy.matrix present" "matrix:" "$(cat "${GH_MAT}")"

# aarch64 cross-compiler
GH_CROSS="${TMPDIR_TEST}/github-cross.yml"
ci_generate_github "aarch64" "mainline" "0" "none" "${GH_CROSS}" "0" "0" 2>/dev/null
assert_contains "github aarch64: cross-compiler install" \
    "gcc-aarch64-linux-gnu" "$(cat "${GH_CROSS}")"

# ── 14-17: ci_generate_gitlab ────────────────────────────────────────────────
echo ""
echo "-- ci_generate_gitlab --"

GL_OUT="${TMPDIR_TEST}/gitlab.yml"
ci_generate_gitlab "x86_64" "mainline" "0" "none" "${GL_OUT}" "0" "0" 2>/dev/null
assert_file_exists "gitlab: output file created" "${GL_OUT}"

gl_content=$(cat "${GL_OUT}")
assert_contains "gitlab: has 'stages:'"  "stages:"  "${gl_content}"
assert_contains "gitlab: has 'script:'"  "script:"  "${gl_content}"

GL_REL="${TMPDIR_TEST}/gitlab-release.yml"
ci_generate_gitlab "x86_64" "mainline" "0" "none" "${GL_REL}" "1" "0" 2>/dev/null
assert_contains "gitlab --release: release stage present" "release:" "$(cat "${GL_REL}")"

# ── 18-21: ci_generate_forgejo ───────────────────────────────────────────────
echo ""
echo "-- ci_generate_forgejo --"

FJ_OUT="${TMPDIR_TEST}/forgejo.yml"
ci_generate_forgejo "x86_64" "mainline" "0" "none" "${FJ_OUT}" "0" "0" 2>/dev/null
assert_file_exists "forgejo: output file created" "${FJ_OUT}"

fj_content=$(cat "${FJ_OUT}")
assert_contains "forgejo: has 'on:'"              "on:"               "${fj_content}"
assert_contains "forgejo: has 'workflow_dispatch'" "workflow_dispatch" "${fj_content}"

FJ_REL="${TMPDIR_TEST}/forgejo-release.yml"
ci_generate_forgejo "x86_64" "mainline" "0" "none" "${FJ_REL}" "1" "0" 2>/dev/null
assert_contains "forgejo --release: release job present" "Create Release" "$(cat "${FJ_REL}")"

# ── 22-25: ci_main routing and flavor ────────────────────────────────────────
echo ""
echo "-- ci_main routing --"

GH_ROUTE="${TMPDIR_TEST}/route-github.yml"
ci_main --provider github --arch x86_64 --output "${GH_ROUTE}" 2>/dev/null
assert_file_exists "ci_main --provider github: file created" "${GH_ROUTE}"

GL_ROUTE="${TMPDIR_TEST}/route-gitlab.yml"
ci_main --provider gitlab --arch x86_64 --output "${GL_ROUTE}" 2>/dev/null
assert_file_exists "ci_main --provider gitlab: file created" "${GL_ROUTE}"

FJ_ROUTE="${TMPDIR_TEST}/route-forgejo.yml"
ci_main --provider forgejo --arch x86_64 --output "${FJ_ROUTE}" 2>/dev/null
assert_file_exists "ci_main --provider forgejo: file created" "${FJ_ROUTE}"

# Flavor appears in generated build command
GH_FLAVOR="${TMPDIR_TEST}/github-flavor.yml"
ci_generate_github "x86_64" "xanmod" "0" "none" "${GH_FLAVOR}" "0" "0" 2>/dev/null
assert_contains "github: flavor=xanmod in build cmd" "xanmod" "$(cat "${GH_FLAVOR}")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
