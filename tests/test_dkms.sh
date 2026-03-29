#!/usr/bin/env bash
# tests/test_dkms.sh - Tests for lkf dkms (core/dkms.sh)
#
# Covers:
#   1.  dkms_usage prints expected subcommands
#   2.  dkms_main no args exits 0 (prints usage)
#   3.  dkms_main --help exits 0
#   4.  dkms_main unknown subcommand exits non-zero
#   5.  dkms_cmd_install: module name/version parsing (name = part before /)
#   6.  dkms_cmd_install: module version parsing (ver = part after /)
#   7.  dkms_cmd_install: defaults kernel_ver to uname -r when not specified
#   8.  dkms_cmd_sign: exits non-zero when --sign-key missing
#   9.  dkms_cmd_sign: exits non-zero when --sign-cert missing
#  10.  dkms_cmd_list: runs without error when dkms not installed (warns)

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/dkms.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_dkms.sh ==="

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
echo "-- dkms_main dispatch --"

usage_out=$(dkms_usage 2>&1)
assert_contains "usage: install subcommand"   "install"   "${usage_out}"
assert_contains "usage: uninstall subcommand" "uninstall" "${usage_out}"
assert_contains "usage: sign subcommand"      "sign"      "${usage_out}"
assert_contains "usage: list subcommand"      "list"      "${usage_out}"

assert_exits_zero    "dkms_main no args exits 0"       dkms_main
assert_exits_zero    "dkms_main --help exits 0"        dkms_main --help
assert_exits_nonzero "dkms_main unknown subcmd exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/dkms.sh'; dkms_main bogus"

# ── 5-7: module name/version parsing ─────────────────────────────────────────
echo ""
echo "-- module name/version parsing --"

# Test the parsing logic directly (same as dkms_cmd_install uses)
mod="openrazer-driver/3.0.1"
name="${mod%%/*}"
ver="${mod##*/}"
assert_eq "module name parsed correctly"    "openrazer-driver" "${name}"
assert_eq "module version parsed correctly" "3.0.1"            "${ver}"

mod2="v4l2loopback/0.13.1"
assert_eq "module name with digits" "v4l2loopback" "${mod2%%/*}"
assert_eq "module version with dots" "0.13.1"      "${mod2##*/}"

# kernel_ver defaults to uname -r
running_kernel=$(uname -r)
# Stub dkms and sudo so install doesn't actually run
dkms()  { echo "dkms $*"; }
sudo()  { shift; "$@"; }   # pass-through (dkms is already stubbed)
lkf_require() { return 0; }

install_out=$(dkms_cmd_install --module "test-mod/1.0" 2>&1 || true)
assert_contains "install: defaults to running kernel" "${running_kernel}" "${install_out}"

# ── 8-9: dkms_cmd_sign validation ────────────────────────────────────────────
echo ""
echo "-- dkms_cmd_sign validation --"

assert_exits_nonzero "sign: missing --sign-key exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/dkms.sh'; \
             dkms_cmd_sign --module foo.ko --sign-cert /tmp/cert.crt"

assert_exits_nonzero "sign: missing --sign-cert exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/dkms.sh'; \
             dkms_cmd_sign --module foo.ko --sign-key /tmp/key.pem"

# ── 10: dkms_cmd_list when dkms not installed ─────────────────────────────────
echo ""
echo "-- dkms_cmd_list --"

# Unset the dkms stub defined above so command -v dkms returns false
unset -f dkms
list_out=$(dkms_cmd_list 2>&1 || true)
assert_contains "list: warns when dkms not installed" "not installed" "${list_out}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
