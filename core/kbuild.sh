#!/usr/bin/env bash
# core/kbuild.sh - Kbuild/Kconfig standalone interface
#
# Exposes the Linux kernel's Kbuild/Kconfig infrastructure as a reusable
# library for out-of-tree projects.  Based on patterns from:
#   masahir0y/kbuild_skeleton   - Kbuild/Kconfig standalone template
#   WangNan0/kbuild-standalone  - Standalone kconfig+kbuild as a library
#
# Use cases:
#   - Build a kernel module with the host kernel's Kbuild
#   - Run menuconfig/nconfig against a custom Kconfig tree
#   - Generate a .config for an out-of-tree project using Kconfig
#   - Validate a .config against a Kconfig tree
#   - Extract Kconfig symbols from a kernel source tree

kbuild_usage() {
    cat <<EOF
lkf kbuild - Kbuild/Kconfig standalone interface

USAGE: lkf kbuild <subcommand> [options]

SUBCOMMANDS:
  module      Build an out-of-tree kernel module
  config      Run a Kconfig configurator (menuconfig, nconfig, xconfig)
  defconfig   Generate a defconfig for a Kconfig tree
  validate    Validate a .config against a Kconfig tree
  symbols     List all Kconfig symbols defined in a source tree
  info        Show Kbuild environment (KDIR, compiler, arch)

OPTIONS (all subcommands):
  --kdir <path>     Kernel build directory [/lib/modules/\$(uname -r)/build]
  --arch <arch>     Target architecture [host arch]
  --cc <compiler>   Compiler [gcc]
  --llvm            Use LLVM=1 LLVM_IAS=1
  --cross <prefix>  Cross-compiler prefix

MODULE OPTIONS:
  --src <path>      Module source directory [current directory]
  --out <path>      Output directory [src directory]
  --target <name>   Make target [modules]
  --install         Run 'make modules_install' after build

CONFIG OPTIONS:
  --kconfig <file>  Path to top-level Kconfig file
  --config <file>   Existing .config to start from
  --tool <name>     Configurator: menuconfig, nconfig, xconfig, oldconfig [menuconfig]

VALIDATE OPTIONS:
  --kconfig <file>  Path to top-level Kconfig file
  --config <file>   .config file to validate [.config]

EXAMPLES:
  # Build a module against the running kernel
  lkf kbuild module --src ./my_module

  # Build against a specific kernel tree
  lkf kbuild module --src ./my_module --kdir /usr/src/linux-6.12

  # Run menuconfig on a custom Kconfig tree
  lkf kbuild config --kconfig ./Kconfig --tool menuconfig

  # Generate defconfig
  lkf kbuild defconfig --kconfig ./Kconfig --out ./

  # List all Kconfig symbols in a kernel source tree
  lkf kbuild symbols --kdir /usr/src/linux-6.12
EOF
}

kbuild_main() {
    [[ $# -eq 0 ]] && { kbuild_usage; return 0; }
    local subcmd="$1"; shift
    case "${subcmd}" in
        module)   kbuild_cmd_module "$@" ;;
        config)   kbuild_cmd_config "$@" ;;
        defconfig) kbuild_cmd_defconfig "$@" ;;
        validate) kbuild_cmd_validate "$@" ;;
        symbols)  kbuild_cmd_symbols "$@" ;;
        info)     kbuild_cmd_info "$@" ;;
        --help|-h) kbuild_usage ;;
        *) lkf_die "Unknown kbuild subcommand: ${subcmd}" ;;
    esac
}

# ── Common option parsing ─────────────────────────────────────────────────────

_kbuild_parse_common() {
    # Sets: KBUILD_KDIR KBUILD_ARCH KBUILD_CC KBUILD_LLVM KBUILD_CROSS
    KBUILD_KDIR="/lib/modules/$(uname -r)/build"
    KBUILD_ARCH="$(uname -m)"
    KBUILD_CC="gcc"
    KBUILD_LLVM=0
    KBUILD_CROSS=""
}

_kbuild_make_flags() {
    local flags=()
    flags+=("ARCH=$(arch_to_kernel_arch "${KBUILD_ARCH}")")
    if [[ "${KBUILD_LLVM}" -eq 1 ]]; then
        flags+=("LLVM=1" "LLVM_IAS=1" "CC=clang" "LD=ld.lld" "AR=llvm-ar"
                "NM=llvm-nm" "STRIP=llvm-strip" "OBJCOPY=llvm-objcopy"
                "OBJDUMP=llvm-objdump" "READELF=llvm-readelf" "HOSTCC=clang")
    else
        flags+=("CC=${KBUILD_CC}")
        [[ -n "${KBUILD_CROSS}" ]] && flags+=("CROSS_COMPILE=${KBUILD_CROSS}")
    fi
    echo "${flags[@]}"
}

# ── lkf kbuild module ─────────────────────────────────────────────────────────

kbuild_cmd_module() {
    _kbuild_parse_common
    local src_dir="${PWD}" out_dir="" target="modules" do_install=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)    KBUILD_KDIR="$2"; shift 2 ;;
            --arch)    KBUILD_ARCH="$2"; shift 2 ;;
            --cc)      KBUILD_CC="$2"; shift 2 ;;
            --llvm)    KBUILD_LLVM=1; shift ;;
            --cross)   KBUILD_CROSS="$2"; shift 2 ;;
            --src)     src_dir="$2"; shift 2 ;;
            --out)     out_dir="$2"; shift 2 ;;
            --target)  target="$2"; shift 2 ;;
            --install) do_install=1; shift ;;
            --help|-h) kbuild_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    [[ -d "${KBUILD_KDIR}" ]] || \
        lkf_die "Kernel build directory not found: ${KBUILD_KDIR}"
    [[ -d "${src_dir}" ]] || \
        lkf_die "Module source directory not found: ${src_dir}"

    local make_flags
    read -ra make_flags <<< "$(_kbuild_make_flags)"

    local make_cmd=(make -C "${KBUILD_KDIR}" M="${src_dir}" "${make_flags[@]}")
    [[ -n "${out_dir}" ]] && make_cmd+=(O="${out_dir}")
    make_cmd+=("${target}")

    lkf_step "Building kernel module: ${src_dir}"
    lkf_info "  KDIR : ${KBUILD_KDIR}"
    lkf_info "  flags: ${make_flags[*]}"
    lkf_info "  cmd  : ${make_cmd[*]}"

    "${make_cmd[@]}"

    if [[ "${do_install}" -eq 1 ]]; then
        lkf_step "Installing module"
        make -C "${KBUILD_KDIR}" M="${src_dir}" "${make_flags[@]}" modules_install
    fi

    lkf_info "Module build complete."
}

# ── lkf kbuild config ─────────────────────────────────────────────────────────

kbuild_cmd_config() {
    _kbuild_parse_common
    local kconfig_file="" config_file="" tool="menuconfig"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)    KBUILD_KDIR="$2"; shift 2 ;;
            --arch)    KBUILD_ARCH="$2"; shift 2 ;;
            --cc)      KBUILD_CC="$2"; shift 2 ;;
            --llvm)    KBUILD_LLVM=1; shift ;;
            --cross)   KBUILD_CROSS="$2"; shift 2 ;;
            --kconfig) kconfig_file="$2"; shift 2 ;;
            --config)  config_file="$2"; shift 2 ;;
            --tool)    tool="$2"; shift 2 ;;
            --help|-h) kbuild_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    local make_flags
    read -ra make_flags <<< "$(_kbuild_make_flags)"

    if [[ -n "${kconfig_file}" ]]; then
        # Out-of-tree Kconfig: use the kernel's conf/mconf tools directly
        local kconfig_dir
        kconfig_dir="$(dirname "${kconfig_file}")"
        local kconfig_tools="${KBUILD_KDIR}/scripts/kconfig"

        [[ -d "${kconfig_tools}" ]] || \
            lkf_die "Kconfig tools not found in ${KBUILD_KDIR}/scripts/kconfig"

        [[ -n "${config_file}" ]] && cp "${config_file}" "${kconfig_dir}/.config"

        case "${tool}" in
            menuconfig) "${kconfig_tools}/mconf" "${kconfig_file}" ;;
            nconfig)    "${kconfig_tools}/nconf" "${kconfig_file}" ;;
            xconfig)    "${kconfig_tools}/qconf" "${kconfig_file}" ;;
            oldconfig)  "${kconfig_tools}/conf" --oldconfig "${kconfig_file}" ;;
            *) lkf_die "Unknown configurator: ${tool}" ;;
        esac
    else
        # In-tree: delegate to kernel's make target
        [[ -d "${KBUILD_KDIR}" ]] || \
            lkf_die "Kernel build directory not found: ${KBUILD_KDIR}"
        [[ -n "${config_file}" ]] && cp "${config_file}" "${KBUILD_KDIR}/.config"
        make -C "${KBUILD_KDIR}" "${make_flags[@]}" "${tool}"
    fi
}

# ── lkf kbuild defconfig ──────────────────────────────────────────────────────

kbuild_cmd_defconfig() {
    _kbuild_parse_common
    local kconfig_file="" out_dir="${PWD}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)    KBUILD_KDIR="$2"; shift 2 ;;
            --arch)    KBUILD_ARCH="$2"; shift 2 ;;
            --cc)      KBUILD_CC="$2"; shift 2 ;;
            --llvm)    KBUILD_LLVM=1; shift ;;
            --cross)   KBUILD_CROSS="$2"; shift 2 ;;
            --kconfig) kconfig_file="$2"; shift 2 ;;
            --out)     out_dir="$2"; shift 2 ;;
            --help|-h) kbuild_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    local make_flags
    read -ra make_flags <<< "$(_kbuild_make_flags)"

    if [[ -n "${kconfig_file}" ]]; then
        local kconfig_tools="${KBUILD_KDIR}/scripts/kconfig"
        [[ -d "${kconfig_tools}" ]] || \
            lkf_die "Kconfig tools not found in ${KBUILD_KDIR}/scripts/kconfig"
        lkf_step "Generating defconfig from ${kconfig_file}"
        (cd "${out_dir}" && "${kconfig_tools}/conf" --defconfig "${kconfig_file}")
    else
        [[ -d "${KBUILD_KDIR}" ]] || \
            lkf_die "Kernel build directory not found: ${KBUILD_KDIR}"
        lkf_step "Generating defconfig in ${KBUILD_KDIR}"
        make -C "${KBUILD_KDIR}" "${make_flags[@]}" defconfig
    fi

    lkf_info "defconfig written to ${out_dir}/.config"
}

# ── lkf kbuild validate ───────────────────────────────────────────────────────

kbuild_cmd_validate() {
    _kbuild_parse_common
    local kconfig_file="" config_file=".config"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)    KBUILD_KDIR="$2"; shift 2 ;;
            --arch)    KBUILD_ARCH="$2"; shift 2 ;;
            --kconfig) kconfig_file="$2"; shift 2 ;;
            --config)  config_file="$2"; shift 2 ;;
            --help|-h) kbuild_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    [[ -f "${config_file}" ]] || lkf_die ".config not found: ${config_file}"

    local make_flags
    read -ra make_flags <<< "$(_kbuild_make_flags)"

    lkf_step "Validating ${config_file}"

    if [[ -n "${kconfig_file}" ]]; then
        local kconfig_tools="${KBUILD_KDIR}/scripts/kconfig"
        [[ -d "${kconfig_tools}" ]] || \
            lkf_die "Kconfig tools not found in ${KBUILD_KDIR}/scripts/kconfig"
        cp "${config_file}" "$(dirname "${kconfig_file}")/.config"
        "${kconfig_tools}/conf" --olddefconfig "${kconfig_file}" && \
            lkf_info "Validation passed." || \
            lkf_die "Validation failed — .config has unresolved symbols."
    else
        [[ -d "${KBUILD_KDIR}" ]] || \
            lkf_die "Kernel build directory not found: ${KBUILD_KDIR}"
        cp "${config_file}" "${KBUILD_KDIR}/.config"
        make -C "${KBUILD_KDIR}" "${make_flags[@]}" olddefconfig && \
            lkf_info "Validation passed." || \
            lkf_die "Validation failed."
    fi
}

# ── lkf kbuild symbols ────────────────────────────────────────────────────────

kbuild_cmd_symbols() {
    _kbuild_parse_common
    local src_dir="" filter=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)   KBUILD_KDIR="$2"; src_dir="$2"; shift 2 ;;
            --src)    src_dir="$2"; shift 2 ;;
            --filter) filter="$2"; shift 2 ;;
            --help|-h) kbuild_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    [[ -z "${src_dir}" ]] && src_dir="${KBUILD_KDIR}"
    [[ -d "${src_dir}" ]] || lkf_die "Source directory not found: ${src_dir}"

    lkf_step "Extracting Kconfig symbols from ${src_dir}"

    local results
    results=$(find "${src_dir}" -name "Kconfig*" -exec \
        grep -hoP '^\s*(bool|tristate|string|int|hex)\s+\K"[^"]+"' {} \; \
        | sort -u)

    if [[ -n "${filter}" ]]; then
        results=$(echo "${results}" | grep -i "${filter}" || true)
    fi

    if [[ -z "${results}" ]]; then
        lkf_warn "No Kconfig symbols found in ${src_dir}"
        return 0
    fi

    echo "${results}"
    lkf_info "$(echo "${results}" | wc -l) symbols found."
}

# ── lkf kbuild info ───────────────────────────────────────────────────────────

kbuild_cmd_info() {
    _kbuild_parse_common

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kdir)  KBUILD_KDIR="$2"; shift 2 ;;
            --arch)  KBUILD_ARCH="$2"; shift 2 ;;
            --cc)    KBUILD_CC="$2"; shift 2 ;;
            --llvm)  KBUILD_LLVM=1; shift ;;
            --cross) KBUILD_CROSS="$2"; shift 2 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    echo "Kbuild environment:"
    echo "  KDIR    : ${KBUILD_KDIR}"
    echo "  ARCH    : $(arch_to_kernel_arch "${KBUILD_ARCH}") (host: ${KBUILD_ARCH})"
    echo "  CC      : ${KBUILD_CC}"
    echo "  LLVM    : ${KBUILD_LLVM}"
    echo "  CROSS   : ${KBUILD_CROSS:-<none>}"

    if [[ -d "${KBUILD_KDIR}" ]]; then
        local kver
        kver=$(cat "${KBUILD_KDIR}/include/config/kernel.release" 2>/dev/null \
            || make -C "${KBUILD_KDIR}" kernelrelease 2>/dev/null \
            || echo "unknown")
        echo "  KVER    : ${kver}"
        echo "  KDIR ok : yes"
    else
        echo "  KDIR ok : NO (directory not found)"
    fi

    local make_flags
    read -ra make_flags <<< "$(_kbuild_make_flags)"
    echo "  flags   : ${make_flags[*]}"
}
