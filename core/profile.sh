#!/usr/bin/env bash
# core/profile.sh - Named build profile management
# Profiles are TOML-like config files stored in ~/.config/lkf/profiles/
# or ${LKF_ROOT}/profiles/

LKF_PROFILE_DIR="${HOME}/.config/lkf/profiles"
LKF_BUILTIN_PROFILE_DIR="${LKF_ROOT}/profiles"

profile_usage() {
    cat <<EOF
lkf profile - Manage named kernel build profiles

USAGE: lkf profile <subcommand> [options]

SUBCOMMANDS:
  list    List available profiles
  show    Show a profile's settings
  create  Create a new profile
  use     Build using a named profile

EXAMPLES:
  lkf profile list
  lkf profile show xanmod-desktop
  lkf profile create --name my-server --base server
  lkf profile use xanmod-desktop --version 6.12
EOF
}

profile_main() {
    [[ $# -eq 0 ]] && { profile_usage; return 0; }
    local subcmd="$1"; shift
    case "${subcmd}" in
        list)   profile_cmd_list ;;
        show)   profile_cmd_show "$@" ;;
        create) profile_cmd_create "$@" ;;
        use)    profile_cmd_use "$@" ;;
        --help|-h) profile_usage ;;
        *) lkf_die "Unknown profile subcommand: ${subcmd}" ;;
    esac
}

profile_cmd_list() {
    echo "Built-in profiles:"
    find "${LKF_BUILTIN_PROFILE_DIR}" -name "*.profile" 2>/dev/null \
        | sed "s|${LKF_BUILTIN_PROFILE_DIR}/||;s|\.profile$||" \
        | sort | sed 's/^/  /'
    echo ""
    echo "User profiles (${LKF_PROFILE_DIR}):"
    find "${LKF_PROFILE_DIR}" -name "*.profile" 2>/dev/null \
        | sed "s|${LKF_PROFILE_DIR}/||;s|\.profile$||" \
        | sort | sed 's/^/  /' || echo "  (none)"
}

profile_cmd_show() {
    local name="${1:-}"
    [[ -z "${name}" ]] && lkf_die "Profile name required"
    local profile_file
    profile_file=$(profile_find "${name}")
    [[ -z "${profile_file}" ]] && lkf_die "Profile not found: ${name}"
    echo "Profile: ${name}"
    echo "────────────────────────────────────────"
    cat "${profile_file}"
}

profile_cmd_create() {
    local name="" base="desktop"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done
    [[ -z "${name}" ]] && lkf_die "--name required"
    lkf_ensure_dir "${LKF_PROFILE_DIR}"
    local dest="${LKF_PROFILE_DIR}/${name}.profile"
    [[ -f "${dest}" ]] && lkf_die "Profile already exists: ${dest}"

    # Copy base profile if it exists
    local base_file
    base_file=$(profile_find "${base}")
    if [[ -n "${base_file}" ]]; then
        cp "${base_file}" "${dest}"
    else
        cat > "${dest}" <<EOF
# lkf build profile: ${name}
# Generated from base: ${base}

flavor = mainline
arch = x86_64
cc = gcc
llvm = false
lto = none
target = desktop
output = deb
EOF
    fi
    lkf_info "Profile created: ${dest}"
    lkf_info "Edit it, then run: lkf profile use ${name} --version <ver>"
}

profile_cmd_use() {
    local name="${1:-}"; shift
    [[ -z "${name}" ]] && lkf_die "Profile name required"
    local profile_file
    profile_file=$(profile_find "${name}")
    [[ -z "${profile_file}" ]] && lkf_die "Profile not found: ${name}"

    # Parse profile and build args array
    local build_args=()
    while IFS=' = ' read -r key val; do
        [[ "${key}" =~ ^#.*$ || -z "${key}" ]] && continue
        val="${val//\"/}"
        case "${key// /}" in
            flavor)      build_args+=(--flavor "${val}") ;;
            arch)        build_args+=(--arch "${val}") ;;
            cc)          build_args+=(--cc "${val}") ;;
            llvm)        [[ "${val}" == "true" ]] && build_args+=(--llvm) ;;
            lto)         [[ "${val}" != "none" ]] && build_args+=(--lto "${val}") ;;
            target)      build_args+=(--target "${val}") ;;
            output)      build_args+=(--output "${val}") ;;
            patch_set)   build_args+=(--patch-set "${val}") ;;
            localversion) build_args+=(--localversion "${val}") ;;
            llvm_version) build_args+=(--llvm-version "${val}") ;;
        esac
    done < "${profile_file}"

    lkf_info "Using profile '${name}': ${build_args[*]} $*"
    source "${LKF_ROOT}/core/build.sh"
    build_main "${build_args[@]}" "$@"
}

profile_find() {
    local name="$1"
    # User profiles take precedence
    [[ -f "${LKF_PROFILE_DIR}/${name}.profile" ]] && \
        echo "${LKF_PROFILE_DIR}/${name}.profile" && return
    [[ -f "${LKF_BUILTIN_PROFILE_DIR}/${name}.profile" ]] && \
        echo "${LKF_BUILTIN_PROFILE_DIR}/${name}.profile" && return
    echo ""
}
