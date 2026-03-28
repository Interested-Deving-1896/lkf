#!/usr/bin/env bash
# core/debug.sh - QEMU + GDB kernel debug environment
#
# Incorporates patterns from:
#   deepseagirl/easylkb - Full QEMU+GDB+debootstrap debug workflow
#   elfmaster/kdress    - vmlinuz -> debuggable vmlinux transformation
#   osresearch/linux-builder - Appliance kernel testing

debug_usage() {
    cat <<EOF
lkf debug - Launch a QEMU kernel debug environment

USAGE: lkf debug [options]

OPTIONS:
  --kernel <path>     Kernel image (vmlinuz or vmlinux) [required]
  --rootfs <path>     Root filesystem image (ext4 .img or cpio)
  --version <ver>     Kernel version (for locating vmlinux/System.map)
  --source-dir <path> Kernel source tree (for GDB symbols)
  --arch <arch>       Target architecture [host arch]
  --memory <mb>       QEMU RAM in MB [2048]
  --cpus <n>          QEMU CPU count [2]
  --port-ssh <port>   Host port for SSH into guest [10021]
  --port-gdb <port>   Host port for GDB remote [1234]
  --kvm               Enable KVM acceleration
  --no-kvm            Disable KVM (use TCG)
  --cmdline <str>     Kernel command line override
  --gdb-init          Print .gdbinit snippet for this session
  --dry-run           Print QEMU command without running

EXAMPLES:
  lkf debug --kernel build/vmlinuz-6.12 --rootfs build/rootfs.img --kvm
  lkf debug --kernel vmlinuz --version 6.12.0 --source-dir ~/linux --gdb-init
EOF
}

debug_main() {
    local kernel="" rootfs="" version="" source_dir="" arch=""
    local memory=2048 cpus=2 port_ssh=10021 port_gdb=1234
    local kvm=1 cmdline="" gdb_init=0 dry_run=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kernel)     kernel="$2"; shift 2 ;;
            --rootfs)     rootfs="$2"; shift 2 ;;
            --version)    version="$2"; shift 2 ;;
            --source-dir) source_dir="$2"; shift 2 ;;
            --arch)       arch="$2"; shift 2 ;;
            --memory)     memory="$2"; shift 2 ;;
            --cpus)       cpus="$2"; shift 2 ;;
            --port-ssh)   port_ssh="$2"; shift 2 ;;
            --port-gdb)   port_gdb="$2"; shift 2 ;;
            --kvm)        kvm=1; shift ;;
            --no-kvm)     kvm=0; shift ;;
            --cmdline)    cmdline="$2"; shift 2 ;;
            --gdb-init)   gdb_init=1; shift ;;
            --dry-run)    dry_run=1; shift ;;
            --help|-h)    debug_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    [[ -z "${kernel}" ]] && lkf_die "--kernel required"
    [[ ! -f "${kernel}" ]] && lkf_die "Kernel not found: ${kernel}"
    [[ -z "${arch}" ]] && arch=$(detect_host_arch)

    # Determine QEMU binary
    local qemu_bin
    case "${arch}" in
        x86_64)  qemu_bin="qemu-system-x86_64" ;;
        aarch64) qemu_bin="qemu-system-aarch64" ;;
        arm)     qemu_bin="qemu-system-arm" ;;
        riscv64) qemu_bin="qemu-system-riscv64" ;;
        *)       qemu_bin="qemu-system-${arch}" ;;
    esac
    lkf_require "${qemu_bin}"

    # Default kernel cmdline (inspired by deepseagirl/easylkb)
    if [[ -z "${cmdline}" ]]; then
        cmdline="console=ttyS0 root=/dev/sda rw nokaslr"
        [[ -z "${rootfs}" ]] && cmdline="console=ttyS0 nokaslr"
    fi

    # Build QEMU command
    local qemu_cmd=(
        "${qemu_bin}"
        -kernel "${kernel}"
        -m "${memory}"
        -smp "${cpus}"
        -append "${cmdline}"
        -nographic
        -serial mon:stdio
        -net nic -net "user,hostfwd=tcp::${port_ssh}-:22"
        -s -S  # GDB server on :1234, wait for connection
    )

    # Override GDB port if non-default
    [[ "${port_gdb}" != "1234" ]] && {
        # Remove -s and add explicit gdb port
        qemu_cmd=("${qemu_cmd[@]/-s/}")
        qemu_cmd+=(-gdb "tcp::${port_gdb}")
    }

    # KVM acceleration
    if [[ "${kvm}" -eq 1 ]]; then
        if [[ -e /dev/kvm ]]; then
            qemu_cmd+=(-enable-kvm -cpu host)
        else
            lkf_warn "/dev/kvm not available. Running without KVM."
        fi
    fi

    # Root filesystem
    if [[ -n "${rootfs}" && -f "${rootfs}" ]]; then
        case "${rootfs}" in
            *.img) qemu_cmd+=(-drive "file=${rootfs},format=raw,if=virtio") ;;
            *.qcow2) qemu_cmd+=(-drive "file=${rootfs},format=qcow2,if=virtio") ;;
            *.cpio*) qemu_cmd+=(-initrd "${rootfs}") ;;
        esac
    fi

    # Print GDB init snippet
    if [[ "${gdb_init}" -eq 1 ]]; then
        local vmlinux=""
        [[ -n "${source_dir}" ]] && vmlinux="${source_dir}/vmlinux"
        [[ -z "${vmlinux}" && -n "${version}" ]] && \
            vmlinux=$(find /usr/lib/debug /boot -name "vmlinux-${version}" 2>/dev/null | head -1)

        cat <<EOF

# Add to ~/.gdbinit:
$([ -n "${vmlinux}" ] && echo "add-auto-load-safe-path $(dirname "${vmlinux}")/scripts/gdb/vmlinux-gdb.py")

# Then run:
$([ -n "${vmlinux}" ] && echo "gdb ${vmlinux}")

# Inside GDB:
(gdb) lx-symbols
(gdb) target remote :${port_gdb}

# SSH into guest (once booted):
ssh root@localhost -p ${port_ssh}
EOF
    fi

    if [[ "${dry_run}" -eq 1 ]]; then
        lkf_info "QEMU command:"
        echo "${qemu_cmd[*]}"
        return 0
    fi

    lkf_step "Launching QEMU (GDB on :${port_gdb}, SSH on :${port_ssh})"
    lkf_info "Connect GDB: target remote :${port_gdb}"
    lkf_info "Connect SSH: ssh root@localhost -p ${port_ssh}"
    lkf_info "Press Ctrl-A X to exit QEMU"
    "${qemu_cmd[@]}"
}
