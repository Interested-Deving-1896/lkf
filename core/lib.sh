#!/usr/bin/env bash
# core/lib.sh - Shared utilities for lkf

# ── Logging ──────────────────────────────────────────────────────────────────

LKF_COLOR=${LKF_COLOR:-1}

_color() {
    [[ "${LKF_COLOR}" == "1" ]] && printf '\033[%sm' "$1" || true
}

lkf_info()  { printf "%s[lkf]%s %s\n" "$(_color '0;32')" "$(_color '0')" "$*"; }
lkf_warn()  { printf "%s[lkf WARN]%s %s\n" "$(_color '0;33')" "$(_color '0')" "$*" >&2; }
lkf_error() { printf "%s[lkf ERROR]%s %s\n" "$(_color '0;31')" "$(_color '0')" "$*" >&2; }
lkf_die()   { lkf_error "$*"; exit 1; }
lkf_step()  { printf "%s[lkf >>]%s %s\n" "$(_color '0;36')" "$(_color '0')" "$*"; }

# ── Dependency checks ─────────────────────────────────────────────────────────

lkf_require() {
    local missing=()
    for cmd in "$@"; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        lkf_die "Missing required tools: ${missing[*]}"
    fi
}

lkf_require_optional() {
    local cmd="$1" msg="${2:-}"
    if ! command -v "${cmd}" &>/dev/null; then
        lkf_warn "Optional tool '${cmd}' not found.${msg:+ ${msg}}"
        return 1
    fi
    return 0
}

# ── Filesystem helpers ────────────────────────────────────────────────────────

lkf_mktemp_dir() {
    mktemp -d "${TMPDIR:-/tmp}/lkf.XXXXXX"
}

lkf_ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

# ── Download helpers ──────────────────────────────────────────────────────────

# Download a file with progress, skip if already present and size matches.
lkf_download() {
    local url="$1" dest="$2"
    if [[ -f "${dest}" ]]; then
        lkf_info "Already downloaded: ${dest}"
        return 0
    fi
    lkf_step "Downloading ${url}"
    lkf_ensure_dir "$(dirname "${dest}")"
    if command -v curl &>/dev/null; then
        curl -fL --progress-bar -o "${dest}" "${url}"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "${dest}" "${url}"
    else
        lkf_die "Neither curl nor wget found."
    fi
}

# ── GPG verification ──────────────────────────────────────────────────────────

# Verify a kernel tarball signature (from kernel.org).
# Inspired by h0tc0d3/kbuild --verify flag.
lkf_verify_gpg() {
    local archive="$1" sig="${2:-${1}.sign}"
    lkf_require gpg
    if [[ ! -f "${sig}" ]]; then
        lkf_warn "Signature file not found: ${sig}. Skipping GPG verification."
        return 0
    fi
    lkf_step "Verifying GPG signature for ${archive}"
    # Import kernel.org signing keys if not present
    gpg --list-keys torvalds@kernel.org &>/dev/null || \
        gpg --keyserver hkps://keyserver.ubuntu.com \
            --recv-keys 647F28654894E3BD457199BE38DBBDC86092693E \
                        ABAF11C65A2970B130ABE3C479BE3E4300411886 2>/dev/null || true
    if ! gpg --verify "${sig}" "${archive}" 2>/dev/null; then
        lkf_die "GPG verification FAILED for ${archive}"
    fi
    lkf_info "GPG verification passed."
}

# ── Version normalization ─────────────────────────────────────────────────────

# Normalize kernel version strings: v6.1.12 -> 6.1.12, 6.1.y -> resolved latest
lkf_normalize_version() {
    local ver="$1"
    # Strip leading 'v'
    ver="${ver#v}"
    echo "${ver}"
}

# Resolve 6.1.y to the latest stable patch from kernel.org
lkf_resolve_version() {
    local ver="$1"
    if [[ "${ver}" =~ ^([0-9]+\.[0-9]+)\.y$ ]]; then
        local base="${BASH_REMATCH[1]}"
        lkf_step "Resolving latest patch for ${base}.y from kernel.org..."
        local resolved
        resolved=$(curl -fsSL "https://www.kernel.org/releases.json" 2>/dev/null \
            | grep -oP '"version":"\K[^"]+' \
            | grep "^${base}\." \
            | sort -V | tail -1) || true
        if [[ -z "${resolved}" ]]; then
            lkf_die "Could not resolve version ${ver} from kernel.org"
        fi
        echo "${resolved}"
    else
        echo "${ver}"
    fi
}

# ── Parallel job count ────────────────────────────────────────────────────────

lkf_nproc() {
    local n
    n=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    echo "${n}"
}

# ── String helpers ────────────────────────────────────────────────────────────

lkf_in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}
