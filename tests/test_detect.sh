#!/usr/bin/env bash
# tests/test_detect.sh - Unit tests for core/detect.sh

set -euo pipefail
LKF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${LKF_ROOT}/core/lib.sh"
source "${LKF_ROOT}/core/detect.sh"

pass=0; fail=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        echo "  PASS: ${desc}"
        pass=$((pass + 1))
    else
        echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"
        fail=$((fail + 1))
    fi
}

assert_nonempty() {
    local desc="$1" val="$2"
    if [[ -n "${val}" ]]; then
        echo "  PASS: ${desc} (got '${val}')"
        pass=$((pass + 1))
    else
        echo "  FAIL: ${desc} — got empty string"
        fail=$((fail + 1))
    fi
}

echo "=== test_detect.sh ==="

# arch_to_kernel_arch
assert_eq "x86_64 -> x86_64"   "x86_64" "$(arch_to_kernel_arch x86_64)"
assert_eq "aarch64 -> arm64"   "arm64"  "$(arch_to_kernel_arch aarch64)"
assert_eq "arm -> arm"         "arm"    "$(arch_to_kernel_arch arm)"
assert_eq "riscv64 -> riscv"   "riscv"  "$(arch_to_kernel_arch riscv64)"

# detect_host_arch returns something
assert_nonempty "detect_host_arch" "$(detect_host_arch)"

# detect_distro returns something
assert_nonempty "detect_distro" "$(detect_distro)"

# detect_pkg_manager returns something
assert_nonempty "detect_pkg_manager" "$(detect_pkg_manager)"

# lkf_normalize_version
assert_eq "strip v prefix"  "6.12.3" "$(lkf_normalize_version v6.12.3)"
assert_eq "no prefix"       "6.12"   "$(lkf_normalize_version 6.12)"

# lkf_nproc returns a number
nproc_val=$(lkf_nproc)
if [[ "${nproc_val}" =~ ^[0-9]+$ ]]; then
    echo "  PASS: lkf_nproc returns integer (${nproc_val})"
    pass=$((pass + 1))
else
    echo "  FAIL: lkf_nproc returned '${nproc_val}'"
    fail=$((fail + 1))
fi

echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
