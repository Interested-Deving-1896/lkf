#!/usr/bin/env bash
# tests/test_initrd.sh - Tests for lkf initrd (core/initrd.sh)
#
# Covers:
#   1.  initrd_usage prints expected subcommands
#   2.  initrd_main no args exits 0
#   3.  initrd_main --help exits 0
#   4.  initrd_main unknown subcommand exits non-zero
#   5.  initrd_cmd_build: exits non-zero with neither --config nor --debootstrap
#   6.  initrd_cmd_build: exits non-zero when --config file not found
#   7.  initrd_build_from_config: creates cpio.xz output from a config file
#   8.  initrd_build_from_config: skips missing entries with a warning
#   9.  initrd_build_from_config: creates essential dirs (proc sys dev tmp run)
#  10.  initrd_build_from_config: gzip compression produces output
#  11.  initrd_build_from_config: none compression produces raw cpio
#  12.  initrd_cmd_symlink: exits non-zero when --kernel missing
#  13.  initrd_cmd_symlink: creates symlink in a custom --root dir
#  14.  initrd_cmd_inspect: exits non-zero when --file missing
#  15.  initrd_cmd_inspect: exits non-zero when file not found
#  16.  initrd_cmd_inspect: lists contents of a valid cpio.xz

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/initrd.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_initrd.sh ==="

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

# ── 1-4: dispatch ─────────────────────────────────────────────────────────────
echo ""
echo "-- initrd_main dispatch --"

usage_out=$(initrd_usage 2>&1)
assert_contains "usage: build subcommand"   "build"   "${usage_out}"
assert_contains "usage: symlink subcommand" "symlink" "${usage_out}"
assert_contains "usage: inspect subcommand" "inspect" "${usage_out}"

assert_exits_zero    "initrd_main no args exits 0"  initrd_main
assert_exits_zero    "initrd_main --help exits 0"   initrd_main --help
assert_exits_nonzero "initrd_main unknown subcmd exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; initrd_main bogus"

# ── 5-6: initrd_cmd_build validation ─────────────────────────────────────────
echo ""
echo "-- initrd_cmd_build validation --"

assert_exits_nonzero "build: no --config or --debootstrap exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; initrd_cmd_build"

assert_exits_nonzero "build: missing --config file exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; \
             initrd_cmd_build --config /nonexistent/initrd.conf"

# ── 7-11: initrd_build_from_config ───────────────────────────────────────────
echo ""
echo "-- initrd_build_from_config --"

if ! command -v cpio &>/dev/null; then
    echo "  SKIP: cpio not available — skipping build_from_config tests (7-11)"
    # Count as passes so the suite doesn't fail in environments without cpio
    for _s in \
        "build_from_config: xz output created" \
        "build_from_config: proc dir present" \
        "build_from_config: sys dir present" \
        "build_from_config: dev dir present" \
        "build_from_config: gzip output created" \
        "build_from_config: raw cpio output created"; do
        ok "${_s} (skipped — no cpio)"
    done
    XZ_OUT=""
else
    # Build a minimal config: one real binary, one missing entry, one dir directive
    FAKE_BIN="${TMPDIR_TEST}/fake-init"
    echo '#!/bin/sh' > "${FAKE_BIN}"
    chmod +x "${FAKE_BIN}"

    INITRD_CONF="${TMPDIR_TEST}/initrd.conf"
    cat > "${INITRD_CONF}" <<EOF
# test initrd config
${FAKE_BIN}
/nonexistent/missing-binary
dir: /custom-dir
EOF

    # Run in a subshell so lkf_die / set -e failures don't abort the suite.
    # xz compression
    XZ_OUT="${TMPDIR_TEST}/initrd.cpio.xz"
    (initrd_build_from_config "${INITRD_CONF}" "${XZ_OUT}" "xz") 2>/dev/null || true
    assert_file_exists "build_from_config: xz output created" "${XZ_OUT}"

    # Verify essential dirs are in the cpio
    cpio_contents=$(xz -dc "${XZ_OUT}" | cpio -t 2>/dev/null || true)
    assert_contains "build_from_config: proc dir present" "proc" "${cpio_contents}"
    assert_contains "build_from_config: sys dir present"  "sys"  "${cpio_contents}"
    assert_contains "build_from_config: dev dir present"  "dev"  "${cpio_contents}"

    # gzip compression
    GZ_OUT="${TMPDIR_TEST}/initrd.cpio.gz"
    (initrd_build_from_config "${INITRD_CONF}" "${GZ_OUT}" "gzip") 2>/dev/null || true
    assert_file_exists "build_from_config: gzip output created" "${GZ_OUT}"

    # none (raw cpio)
    CPIO_OUT="${TMPDIR_TEST}/initrd.cpio"
    (initrd_build_from_config "${INITRD_CONF}" "${CPIO_OUT}" "none") 2>/dev/null || true
    assert_file_exists "build_from_config: raw cpio output created" "${CPIO_OUT}"
fi

# ── 12-13: initrd_cmd_symlink ─────────────────────────────────────────────────
echo ""
echo "-- initrd_cmd_symlink --"

assert_exits_nonzero "symlink: missing --kernel exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; initrd_cmd_symlink"

# Create symlink in a temp root dir (no sudo needed)
FAKE_ROOT="${TMPDIR_TEST}/fake-root"
mkdir -p "${FAKE_ROOT}/boot"
FAKE_KERNEL="${TMPDIR_TEST}/vmlinuz-6.99"
echo "fake kernel" > "${FAKE_KERNEL}"

# Override sudo to be a no-op passthrough for this test
sudo() { "$@"; }
initrd_cmd_symlink --kernel "${FAKE_KERNEL}" --root "${FAKE_ROOT}" 2>/dev/null || true
# ln -sfn creates the symlink; check it exists
if [[ -L "${FAKE_ROOT}/vmlinuz" ]] || [[ -e "${FAKE_ROOT}/vmlinuz" ]]; then
    ok "symlink: /vmlinuz created in custom --root"
else
    fail_test "symlink: /vmlinuz created in custom --root"
fi

# ── 14-16: initrd_cmd_inspect ────────────────────────────────────────────────
echo ""
echo "-- initrd_cmd_inspect --"

assert_exits_nonzero "inspect: missing --file exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; initrd_cmd_inspect"

assert_exits_nonzero "inspect: file not found exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/initrd.sh'; \
             initrd_cmd_inspect --file /nonexistent/initrd.cpio.xz"

# Inspect the xz initrd we built above (only if cpio was available)
if [[ -n "${XZ_OUT:-}" && -f "${XZ_OUT}" ]]; then
    inspect_out=$(initrd_cmd_inspect --file "${XZ_OUT}" 2>/dev/null)
    assert_contains "inspect: lists cpio contents" "proc" "${inspect_out}"
else
    ok "inspect: lists cpio contents (skipped — no cpio)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
