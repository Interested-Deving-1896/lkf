#!/usr/bin/env bash
# tests/test_toolchain.sh - Tests for lkf toolchain (core/toolchain.sh)
#
# Covers:
#   1.  _DEPS_APT map contains expected core packages
#   2.  _DEPS_PACMAN map contains expected core packages
#   3.  _DEPS_DNF map contains expected core packages
#   4.  _DEPS_APK map contains expected core packages
#   5.  _DEPS_LLVM_APT map contains clang, llvm, lld
#   6.  _DEPS_LLVM_PACMAN map contains clang, llvm, lld
#   7.  _DEPS_DEBUG_APT map contains qemu and gdb entries
#   8.  toolchain_install_deps: nix path prints guidance when not in nix-shell
#   9.  toolchain_install_deps: nix path detects IN_NIX_SHELL and skips install
#  10.  toolchain_install_deps: unknown pm warns and exits 0
#  11.  toolchain_install_cross: apt/aarch64 emits correct package name
#  12.  toolchain_install_cross: apt/arm emits correct package name
#  13.  toolchain_install_cross: apt/riscv64 emits correct package name
#  14.  toolchain_install_cross: unknown arch warns
#  15.  toolchain_install_llvm: unknown pm warns

set -euo pipefail

LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/lib.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/detect.sh"
# shellcheck disable=SC1090
source "${LKF_ROOT}/core/toolchain.sh"

pass=0; fail=0
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== test_toolchain.sh ==="

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

# ── 1-7: dependency maps ──────────────────────────────────────────────────────
echo ""
echo "-- dependency maps --"

# APT core deps
apt_vals="${_DEPS_APT[*]}"
assert_contains "_DEPS_APT: gcc"          "gcc"           "${apt_vals}"
assert_contains "_DEPS_APT: make"         "make"          "${apt_vals}"
assert_contains "_DEPS_APT: bison"        "bison"         "${apt_vals}"
assert_contains "_DEPS_APT: libssl-dev"   "libssl-dev"    "${apt_vals}"
assert_contains "_DEPS_APT: python3"      "python3"       "${apt_vals}"

# Pacman core deps
pacman_vals="${_DEPS_PACMAN[*]}"
assert_contains "_DEPS_PACMAN: gcc"       "gcc"           "${pacman_vals}"
assert_contains "_DEPS_PACMAN: base-devel" "base-devel"   "${pacman_vals}"

# DNF core deps
dnf_vals="${_DEPS_DNF[*]}"
assert_contains "_DEPS_DNF: gcc"          "gcc"           "${dnf_vals}"
assert_contains "_DEPS_DNF: bison"        "bison"         "${dnf_vals}"

# APK core deps
apk_vals="${_DEPS_APK[*]}"
assert_contains "_DEPS_APK: build-base"   "build-base"    "${apk_vals}"
assert_contains "_DEPS_APK: gcc"          "gcc"           "${apk_vals}"

# LLVM deps
llvm_apt_vals="${_DEPS_LLVM_APT[*]}"
assert_contains "_DEPS_LLVM_APT: clang"   "clang"         "${llvm_apt_vals}"
assert_contains "_DEPS_LLVM_APT: llvm"    "llvm"          "${llvm_apt_vals}"
assert_contains "_DEPS_LLVM_APT: lld"     "lld"           "${llvm_apt_vals}"

llvm_pacman_vals="${_DEPS_LLVM_PACMAN[*]}"
assert_contains "_DEPS_LLVM_PACMAN: clang" "clang"        "${llvm_pacman_vals}"
assert_contains "_DEPS_LLVM_PACMAN: lld"   "lld"          "${llvm_pacman_vals}"

# Debug deps
debug_apt_vals="${_DEPS_DEBUG_APT[*]}"
assert_contains "_DEPS_DEBUG_APT: qemu"   "qemu"          "${debug_apt_vals}"
assert_contains "_DEPS_DEBUG_APT: gdb"    "gdb"           "${debug_apt_vals}"

# ── 8-10: toolchain_install_deps special paths ───────────────────────────────
echo ""
echo "-- toolchain_install_deps special paths --"

# Stub detect_pkg_manager and sudo/apt-get/pacman/etc. to avoid real installs
detect_pkg_manager() { echo "nix"; }
sudo() { echo "sudo: $*"; }

# nix path outside nix-shell: should print guidance
unset IN_NIX_SHELL
nix_out=$(toolchain_install_deps 2>&1)
assert_contains "nix: guidance when not in nix-shell" "nix" "${nix_out}"

# nix path inside nix-shell: should say deps are available
# shellcheck disable=SC2034  # read by toolchain_install_deps
IN_NIX_SHELL=1
nix_shell_out=$(toolchain_install_deps 2>&1)
assert_contains "nix: detects IN_NIX_SHELL" "available" "${nix_shell_out}"
unset IN_NIX_SHELL

# unknown pm: warns and exits 0
detect_pkg_manager() { echo "unknown-pm-xyz"; }
assert_exits_zero "unknown pm: exits 0 with warning" toolchain_install_deps

# ── 11-14: toolchain_install_cross ───────────────────────────────────────────
echo ""
echo "-- toolchain_install_cross --"

# Stub detect_pkg_manager to apt; stub sudo so it records the full command
detect_pkg_manager() { echo "apt"; }
APT_LOG="${TMPDIR_TEST}/apt.log"
# sudo wraps apt-get, so stub sudo to capture the full invocation
sudo() { echo "sudo $*" >> "${APT_LOG}"; }

toolchain_install_cross "aarch64" 2>/dev/null || true
assert_contains "cross aarch64: gcc-aarch64-linux-gnu" \
    "gcc-aarch64-linux-gnu" "$(cat "${APT_LOG}")"

true > "${APT_LOG}"
toolchain_install_cross "arm" 2>/dev/null || true
assert_contains "cross arm: gcc-arm-linux-gnueabihf" \
    "gcc-arm-linux-gnueabihf" "$(cat "${APT_LOG}")"

true > "${APT_LOG}"
toolchain_install_cross "riscv64" 2>/dev/null || true
assert_contains "cross riscv64: gcc-riscv64-linux-gnu" \
    "gcc-riscv64-linux-gnu" "$(cat "${APT_LOG}")"

# Unknown arch warns (exits 0)
assert_exits_zero "cross unknown arch: exits 0 with warning" \
    toolchain_install_cross "sparc"

# ── 15: toolchain_install_llvm unknown pm ────────────────────────────────────
echo ""
echo "-- toolchain_install_llvm --"

detect_pkg_manager() { echo "unknown-pm-xyz"; }
assert_exits_zero "install_llvm: unknown pm exits 0 with warning" \
    toolchain_install_llvm

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
