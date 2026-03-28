#!/usr/bin/env bash
# core/dkms.sh - DKMS module management alongside kernel builds
# Inspired by h0tc0d3/kbuild DKMS_INSTALL, DKMS_UNINSTALL, DKMS_SIGN options

dkms_usage() {
    cat <<EOF
lkf dkms - Manage DKMS modules for a kernel version

USAGE: lkf dkms <subcommand> [options]

SUBCOMMANDS:
  install    Install DKMS modules for a kernel version
  uninstall  Uninstall DKMS modules
  sign       Sign DKMS modules for Secure Boot
  list       List installed DKMS modules

OPTIONS:
  --module <name/ver>   DKMS module (e.g. openrazer-driver/3.0.1) [repeatable]
  --kernel-ver <ver>    Kernel version [running kernel]
  --sign-key <path>     MOK private key for signing
  --sign-cert <path>    MOK certificate for signing

EXAMPLES:
  lkf dkms install --module openrazer-driver/3.0.1 --kernel-ver 6.12.0-lkf
  lkf dkms sign --module razerkbd.ko --sign-key mok.key --sign-cert mok.crt
  lkf dkms list
EOF
}

dkms_main() {
    [[ $# -eq 0 ]] && { dkms_usage; return 0; }
    local subcmd="$1"; shift
    case "${subcmd}" in
        install)   dkms_cmd_install "$@" ;;
        uninstall) dkms_cmd_uninstall "$@" ;;
        sign)      dkms_cmd_sign "$@" ;;
        list)      dkms_cmd_list "$@" ;;
        --help|-h) dkms_usage ;;
        *) lkf_die "Unknown dkms subcommand: ${subcmd}" ;;
    esac
}

dkms_cmd_install() {
    local modules=() kernel_ver=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module)     modules+=("$2"); shift 2 ;;
            --kernel-ver) kernel_ver="$2"; shift 2 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done
    [[ -z "${kernel_ver}" ]] && kernel_ver=$(uname -r)
    lkf_require dkms

    for mod in "${modules[@]}"; do
        local name="${mod%%/*}" ver="${mod##*/}"
        lkf_step "Installing DKMS module: ${name}/${ver} for kernel ${kernel_ver}"
        sudo dkms install "${name}/${ver}" -k "${kernel_ver}" || \
            lkf_warn "DKMS install failed for ${name}/${ver}"
    done
}

dkms_cmd_uninstall() {
    local modules=() kernel_ver=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module)     modules+=("$2"); shift 2 ;;
            --kernel-ver) kernel_ver="$2"; shift 2 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done
    [[ -z "${kernel_ver}" ]] && kernel_ver=$(uname -r)
    lkf_require dkms

    for mod in "${modules[@]}"; do
        local name="${mod%%/*}" ver="${mod##*/}"
        lkf_step "Uninstalling DKMS module: ${name}/${ver}"
        sudo dkms remove "${name}/${ver}" -k "${kernel_ver}" --all || true
    done
}

dkms_cmd_sign() {
    local modules=() sign_key="" sign_cert=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module)    modules+=("$2"); shift 2 ;;
            --sign-key)  sign_key="$2"; shift 2 ;;
            --sign-cert) sign_cert="$2"; shift 2 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done
    [[ -z "${sign_key}" || -z "${sign_cert}" ]] && \
        lkf_die "--sign-key and --sign-cert required"

    local sign_tool
    sign_tool=$(find /usr/src/linux-headers-"$(uname -r)" \
        -name "sign-file" 2>/dev/null | head -1)
    [[ -z "${sign_tool}" ]] && lkf_die "sign-file tool not found in kernel headers"

    for mod in "${modules[@]}"; do
        lkf_step "Signing module: ${mod}"
        sudo "${sign_tool}" sha256 "${sign_key}" "${sign_cert}" "${mod}"
    done
}

dkms_cmd_list() {
    if command -v dkms &>/dev/null; then
        dkms status
    else
        lkf_warn "dkms not installed."
    fi
}
