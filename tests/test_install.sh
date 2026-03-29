#!/usr/bin/env bash
# tests/test_install.sh - Tests for lkf install (core/install.sh)
#
# Covers:
#   1.  install_usage prints expected options
#   2.  install_main --help exits 0
#   3.  install_main unknown option exits non-zero
#   4.  install_main: missing --kernel file exits non-zero
#   5.  install_main: missing --initrd file exits non-zero
#   6.  install_main: copies kernel to boot dir with versioned name
#   7.  install_main: copies initrd to boot dir with versioned name
#   8.  install_main: unversioned kernel name when --version not given
#   9.  install_main: --deb path is passed to dpkg (stubbed)
#  10.  install_main: --rpm path is passed to rpm (stubbed)

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/install.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_install.sh ==="

ok()        { echo "  PASS: $1"; pass=$(( pass + 1 )); }
fail_test() { echo "  FAIL: $1"; fail=$(( fail + 1 )); }

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then ok "${desc}"
    else fail_test "${desc} — '${needle}' not found"; fi
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

# Fake files
FAKE_KERNEL="${TMPDIR_TEST}/vmlinuz"
FAKE_INITRD="${TMPDIR_TEST}/initrd.cpio.xz"
FAKE_BOOT="${TMPDIR_TEST}/boot"
mkdir -p "${FAKE_BOOT}"
echo "fake kernel" > "${FAKE_KERNEL}"
echo "fake initrd" > "${FAKE_INITRD}"

# Override sudo to passthrough (we're writing to a temp dir, not /boot)
sudo() { "$@"; }

# ── 1-3: dispatch and validation ─────────────────────────────────────────────
echo ""
echo "-- install_main dispatch --"

usage_out=$(install_usage 2>&1)
assert_contains "usage: --kernel option"   "--kernel"   "${usage_out}"
assert_contains "usage: --initrd option"   "--initrd"   "${usage_out}"
assert_contains "usage: --version option"  "--version"  "${usage_out}"
assert_contains "usage: --symlinks option" "--symlinks" "${usage_out}"
assert_contains "usage: --deb option"      "--deb"      "${usage_out}"

assert_exits_zero    "install_main --help exits 0" install_main --help
assert_exits_nonzero "install_main unknown option exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/install.sh'; install_main --bogus"

# ── 4-5: missing file validation ─────────────────────────────────────────────
echo ""
echo "-- install_main file validation --"

assert_exits_nonzero "install: missing --kernel file exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/install.sh'; sudo() { \"\$@\"; }; \
             install_main --kernel /nonexistent/vmlinuz \
               --boot-dir '${FAKE_BOOT}'"

assert_exits_nonzero "install: missing --initrd file exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/install.sh'; sudo() { \"\$@\"; }; \
             install_main --kernel '${FAKE_KERNEL}' \
               --initrd /nonexistent/initrd.cpio.xz \
               --boot-dir '${FAKE_BOOT}'"

# ── 6-8: kernel and initrd copy ───────────────────────────────────────────────
echo ""
echo "-- install_main file copy --"

BOOT1="${TMPDIR_TEST}/boot1"
mkdir -p "${BOOT1}"
install_main \
    --kernel "${FAKE_KERNEL}" \
    --initrd "${FAKE_INITRD}" \
    --version "6.99.0-lkf" \
    --boot-dir "${BOOT1}" 2>/dev/null
assert_file_exists "install: kernel copied with version" "${BOOT1}/vmlinuz-6.99.0-lkf"
assert_file_exists "install: initrd copied with version" "${BOOT1}/initrd.img-6.99.0-lkf"

BOOT2="${TMPDIR_TEST}/boot2"
mkdir -p "${BOOT2}"
install_main \
    --kernel "${FAKE_KERNEL}" \
    --boot-dir "${BOOT2}" 2>/dev/null
assert_file_exists "install: unversioned kernel name" "${BOOT2}/vmlinuz"

# ── 9-10: package install stubs ───────────────────────────────────────────────
echo ""
echo "-- install_main package stubs --"

# Stub dpkg and rpm to record calls
STUB_LOG="${TMPDIR_TEST}/stub.log"
dpkg() { echo "dpkg $*" >> "${STUB_LOG}"; }
rpm()  { echo "rpm $*"  >> "${STUB_LOG}"; }

install_main --deb "/tmp/linux-image-6.99.deb" 2>/dev/null || true
assert_contains "install: --deb calls dpkg" "dpkg" "$(cat "${STUB_LOG}" 2>/dev/null)"

install_main --rpm "/tmp/kernel-6.99.rpm" 2>/dev/null || true
assert_contains "install: --rpm calls rpm" "rpm" "$(cat "${STUB_LOG}" 2>/dev/null)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
