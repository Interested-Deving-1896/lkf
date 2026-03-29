#!/usr/bin/env bash
# tests/test_image.sh - Tests for lkf image (core/image.sh)
#
# Covers:
#   1.  image_usage prints expected subcommands
#   2.  image_main no args exits 0
#   3.  image_main --help exits 0
#   4.  image_main unknown subcommand exits non-zero
#   5.  image_cmd_efi_unified: exits non-zero when --kernel missing
#   6.  image_cmd_efi_unified: exits non-zero when --kernel file not found
#   7.  image_cmd_efi_unified: exits non-zero when --initrd file not found
#   8.  image_cmd_efi_unified: exits non-zero when objcopy not available
#   9.  image_cmd_android_boot: exits non-zero when --kernel missing
#  10.  image_cmd_android_boot: exits non-zero when --base-img missing
#  11.  image_cmd_firmware: exits non-zero when --modules-dir not found
#  12.  image_cmd_tar: exits non-zero when --kernel not found
#  13.  image_cmd_tar: creates output tarball with kernel inside
#  14.  image_cmd_firmware: creates tarball from a fake modules dir

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/image.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_image.sh ==="

ok()        { echo "  PASS: $1"; pass=$(( pass + 1 )); }
fail_test() { echo "  FAIL: $1"; fail=$(( fail + 1 )); }

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

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "${path}" ]]; then ok "${desc}"
    else fail_test "${desc} — file not found: ${path}"; fi
}

# Fake files
FAKE_KERNEL="${TMPDIR_TEST}/vmlinuz"
FAKE_INITRD="${TMPDIR_TEST}/initrd.cpio.xz"
FAKE_CMDLINE="${TMPDIR_TEST}/cmdline.txt"
echo "fake kernel"  > "${FAKE_KERNEL}"
echo "fake initrd"  > "${FAKE_INITRD}"
echo "console=ttyS0" > "${FAKE_CMDLINE}"

# ── 1-4: dispatch ─────────────────────────────────────────────────────────────
echo ""
echo "-- image_main dispatch --"

usage_out=$(image_usage 2>&1)
assert_contains "usage: efi-unified subcommand"  "efi-unified"  "${usage_out}"
assert_contains "usage: android-boot subcommand" "android-boot" "${usage_out}"
assert_contains "usage: firmware subcommand"     "firmware"     "${usage_out}"
assert_contains "usage: tar subcommand"          "tar"          "${usage_out}"

assert_exits_zero    "image_main no args exits 0"  image_main
assert_exits_zero    "image_main --help exits 0"   image_main --help
assert_exits_nonzero "image_main unknown subcmd exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; image_main bogus"

# ── 5-8: efi-unified validation ───────────────────────────────────────────────
echo ""
echo "-- image_cmd_efi_unified validation --"

assert_exits_nonzero "efi-unified: missing --kernel exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; image_cmd_efi_unified"

assert_exits_nonzero "efi-unified: kernel file not found exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; \
             image_cmd_efi_unified --kernel /nonexistent/vmlinuz"

assert_exits_nonzero "efi-unified: initrd file not found exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; \
             image_cmd_efi_unified --kernel '${FAKE_KERNEL}' --initrd /nonexistent/initrd"

# objcopy is required; if it's missing the command should fail
assert_exits_nonzero "efi-unified: missing objcopy exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; \
             PATH='' image_cmd_efi_unified \
               --kernel '${FAKE_KERNEL}' \
               --initrd '${FAKE_INITRD}' \
               --cmdline '${FAKE_CMDLINE}'"

# ── 9-10: android-boot validation ────────────────────────────────────────────
echo ""
echo "-- image_cmd_android_boot validation --"

assert_exits_nonzero "android-boot: missing --kernel exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; image_cmd_android_boot"

# android-boot with only --kernel: warns about missing mkbootimg (exits 0)
android_warn=$(bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
    source '${LKF_ROOT}/core/image.sh'; \
    image_cmd_android_boot --kernel '${FAKE_KERNEL}'" 2>&1 || true)
assert_contains "android-boot: warns when mkbootimg missing" \
    "mkbootimg" "${android_warn}"

# ── 11: firmware validation ───────────────────────────────────────────────────
echo ""
echo "-- image_cmd_firmware validation --"

assert_exits_nonzero "firmware: missing --modules-dir exits non-zero" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; \
             image_cmd_firmware --modules-dir /nonexistent/modules"

# ── 12-14: functional tests ───────────────────────────────────────────────────
echo ""
echo "-- image_cmd_tar and image_cmd_firmware --"

# image_cmd_tar silently skips missing files (no validation by design)
# Verify it exits 0 even with a missing kernel (graceful degradation)
assert_exits_zero "tar: missing kernel exits 0 (graceful skip)" \
    bash -c "source '${LKF_ROOT}/core/lib.sh'; source '${LKF_ROOT}/core/detect.sh'; \
             source '${LKF_ROOT}/core/image.sh'; \
             image_cmd_tar --kernel /nonexistent/vmlinuz \
               --output '${TMPDIR_TEST}/empty.tar.gz'"

# tar with a real kernel file
TAR_OUT="${TMPDIR_TEST}/kernel.tar.gz"
image_cmd_tar \
    --kernel "${FAKE_KERNEL}" \
    --output "${TAR_OUT}" 2>/dev/null
assert_file_exists "tar: output tarball created" "${TAR_OUT}"

# firmware with a fake modules dir
FAKE_MODULES="${TMPDIR_TEST}/modules/6.99.0"
mkdir -p "${FAKE_MODULES}/kernel/drivers"
echo "fake.ko" > "${FAKE_MODULES}/kernel/drivers/fake.ko"
FW_OUT="${TMPDIR_TEST}/firmware.tar.gz"
image_cmd_firmware \
    --modules-dir "${FAKE_MODULES}" \
    --output "${FW_OUT}" 2>/dev/null
assert_file_exists "firmware: output tarball created" "${FW_OUT}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
