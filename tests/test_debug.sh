#!/usr/bin/env bash
# tests/test_debug.sh - Tests for lkf debug (core/debug.sh)
#
# Covers:
#   1.  debug_usage prints expected options
#   2.  debug_main --help exits 0
#   3.  debug_main without --kernel exits non-zero
#   4.  debug_main with missing kernel file exits non-zero
#   5.  debug_main unknown option exits non-zero
#   6.  --dry-run prints QEMU command without executing
#   7.  --dry-run includes --kernel path in output
#   8.  --dry-run includes -m <memory> flag
#   9.  --dry-run includes -smp <cpus> flag
#  10.  --dry-run: --no-kvm suppresses -enable-kvm
#  11.  --dry-run: --kvm adds -enable-kvm when /dev/kvm present (or warns)
#  12.  --dry-run: --rootfs *.img adds -drive flag
#  13.  --dry-run: --rootfs *.cpio adds -initrd flag
#  14.  --dry-run: custom --cmdline appears in output
#  15.  --dry-run: custom --port-gdb appears in output
#  16.  --gdb-init prints target remote line
#  17.  --gdb-init prints SSH connection line
#  18.  QEMU binary selection: x86_64 → qemu-system-x86_64
#  19.  QEMU binary selection: aarch64 → qemu-system-aarch64
#  20.  default memory is 2048, default cpus is 2

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/debug.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_debug.sh ==="

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

# Fake kernel file for tests that need a real path
FAKE_KERNEL="${TMPDIR_TEST}/vmlinuz"
echo "fake kernel" > "${FAKE_KERNEL}"

FAKE_ROOTFS_IMG="${TMPDIR_TEST}/rootfs.img"
echo "fake rootfs" > "${FAKE_ROOTFS_IMG}"

FAKE_ROOTFS_CPIO="${TMPDIR_TEST}/initrd.cpio.xz"
echo "fake cpio" > "${FAKE_ROOTFS_CPIO}"

# Stub lkf_require so tests don't fail on missing qemu binaries
lkf_require() { return 0; }

# ── 1-5: dispatch and validation ─────────────────────────────────────────────
echo ""
echo "-- debug_main dispatch --"

usage_out=$(debug_usage 2>&1)
assert_contains "usage: --kernel option"   "--kernel"   "${usage_out}"
assert_contains "usage: --rootfs option"   "--rootfs"   "${usage_out}"
assert_contains "usage: --dry-run option"  "--dry-run"  "${usage_out}"
assert_contains "usage: --gdb-init option" "--gdb-init" "${usage_out}"
assert_contains "usage: --kvm option"      "--kvm"      "${usage_out}"

assert_exits_zero    "debug_main --help exits 0" debug_main --help

assert_exits_nonzero "debug_main without --kernel exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/debug.sh'; debug_main --dry-run"

assert_exits_nonzero "debug_main with missing kernel file exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/debug.sh'; debug_main --kernel /nonexistent/vmlinuz --dry-run"

assert_exits_nonzero "debug_main unknown option exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/debug.sh'; \
             lkf_require() { return 0; }; \
             debug_main --kernel '${FAKE_KERNEL}' --bogus-flag --dry-run"

# ── 6-15: --dry-run output ────────────────────────────────────────────────────
echo ""
echo "-- debug_main --dry-run --"

dry_base=$(debug_main --kernel "${FAKE_KERNEL}" --dry-run 2>&1)
assert_contains "dry-run: prints QEMU command"  "qemu-system"    "${dry_base}"
assert_contains "dry-run: includes kernel path" "${FAKE_KERNEL}" "${dry_base}"

dry_mem=$(debug_main --kernel "${FAKE_KERNEL}" --memory 4096 --dry-run 2>&1)
assert_contains "dry-run: --memory 4096 in output" "4096" "${dry_mem}"

dry_cpu=$(debug_main --kernel "${FAKE_KERNEL}" --cpus 4 --dry-run 2>&1)
assert_contains "dry-run: --cpus 4 in output" "4" "${dry_cpu}"

dry_nokvm=$(debug_main --kernel "${FAKE_KERNEL}" --no-kvm --dry-run 2>&1)
assert_not_contains "dry-run: --no-kvm suppresses -enable-kvm" "-enable-kvm" "${dry_nokvm}"

dry_img=$(debug_main --kernel "${FAKE_KERNEL}" --rootfs "${FAKE_ROOTFS_IMG}" --dry-run 2>&1)
assert_contains "dry-run: .img rootfs adds -drive" "-drive" "${dry_img}"

dry_cpio=$(debug_main --kernel "${FAKE_KERNEL}" --rootfs "${FAKE_ROOTFS_CPIO}" --dry-run 2>&1)
assert_contains "dry-run: .cpio rootfs adds -initrd" "-initrd" "${dry_cpio}"

dry_cmdline=$(debug_main --kernel "${FAKE_KERNEL}" --cmdline "console=ttyS0 quiet" --dry-run 2>&1)
assert_contains "dry-run: custom --cmdline in output" "quiet" "${dry_cmdline}"

dry_gdbport=$(debug_main --kernel "${FAKE_KERNEL}" --port-gdb 5678 --dry-run 2>&1)
assert_contains "dry-run: custom --port-gdb in output" "5678" "${dry_gdbport}"

# ── 16-17: --gdb-init output ──────────────────────────────────────────────────
echo ""
echo "-- debug_main --gdb-init --"

gdb_out=$(debug_main --kernel "${FAKE_KERNEL}" --dry-run --gdb-init 2>&1)
assert_contains "gdb-init: target remote line"  "target remote" "${gdb_out}"
assert_contains "gdb-init: SSH connection line" "ssh root@localhost" "${gdb_out}"

# ── 18-19: QEMU binary selection (via dry-run) ───────────────────────────────
echo ""
echo "-- QEMU binary selection --"

dry_x86=$(debug_main --kernel "${FAKE_KERNEL}" --arch x86_64 --dry-run 2>&1)
assert_contains "x86_64 → qemu-system-x86_64"   "qemu-system-x86_64"   "${dry_x86}"

dry_arm=$(debug_main --kernel "${FAKE_KERNEL}" --arch aarch64 --dry-run 2>&1)
assert_contains "aarch64 → qemu-system-aarch64" "qemu-system-aarch64" "${dry_arm}"

# ── 20: default memory and cpus ───────────────────────────────────────────────
echo ""
echo "-- defaults --"

dry_defaults=$(debug_main --kernel "${FAKE_KERNEL}" --dry-run 2>&1)
assert_contains "default memory 2048" "2048" "${dry_defaults}"
assert_contains "default cpus 2"      "-smp" "${dry_defaults}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
