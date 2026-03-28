#!/usr/bin/env bash
# core/install.sh - Kernel installation and boot symlink management
#
# Incorporates patterns from:
#   kodx/symlink-initrd-kernel-in-root - /vmlinuz, /initrd.img symlinks + pacman hook
#   h0tc0d3/kbuild                     - mkinitcpio integration, System.map copy
#   deepseagirl/easylkb                - SSH key setup for debug images

install_usage() {
    cat <<EOF
lkf install - Install kernel and manage boot entries

USAGE: lkf install [options]

OPTIONS:
  --kernel <path>       Kernel image to install
  --initrd <path>       initrd image to install
  --version <ver>       Kernel version string (used for filenames)
  --boot-dir <path>     Boot directory [/boot]
  --symlinks            Create /vmlinuz and /initrd.img symlinks
  --mkinitcpio <name>   Run mkinitcpio -p <name> after install (Arch Linux)
  --update-grub         Run update-grub / grub-mkconfig after install
  --update-bootloader   Run bootctl update (systemd-boot)
  --deb <path>          Install a .deb kernel package
  --rpm <path>          Install an .rpm kernel package

EXAMPLES:
  lkf install --deb linux-image-6.12.0-lkf_amd64.deb
  lkf install --kernel vmlinuz --initrd initrd.cpio.xz --version 6.12.0-lkf --symlinks
  lkf install --kernel vmlinuz --mkinitcpio linux-lkf --update-grub
EOF
}

install_main() {
    local kernel="" initrd="" version="" boot_dir="/boot"
    local symlinks=0 mkinitcpio_conf="" update_grub=0 update_bootloader=0
    local deb_pkg="" rpm_pkg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kernel)           kernel="$2"; shift 2 ;;
            --initrd)           initrd="$2"; shift 2 ;;
            --version)          version="$2"; shift 2 ;;
            --boot-dir)         boot_dir="$2"; shift 2 ;;
            --symlinks)         symlinks=1; shift ;;
            --mkinitcpio)       mkinitcpio_conf="$2"; shift 2 ;;
            --update-grub)      update_grub=1; shift ;;
            --update-bootloader) update_bootloader=1; shift ;;
            --deb)              deb_pkg="$2"; shift 2 ;;
            --rpm)              rpm_pkg="$2"; shift 2 ;;
            --help|-h)          install_usage; return 0 ;;
            *) lkf_die "Unknown option: $1" ;;
        esac
    done

    # Package-based install
    if [[ -n "${deb_pkg}" ]]; then
        lkf_step "Installing .deb package: ${deb_pkg}"
        sudo dpkg -i "${deb_pkg}"
    elif [[ -n "${rpm_pkg}" ]]; then
        lkf_step "Installing .rpm package: ${rpm_pkg}"
        sudo rpm -ivh "${rpm_pkg}"
    fi

    # Manual install
    if [[ -n "${kernel}" ]]; then
        [[ ! -f "${kernel}" ]] && lkf_die "Kernel not found: ${kernel}"
        local dest_name="vmlinuz${version:+-${version}}"
        lkf_step "Installing kernel -> ${boot_dir}/${dest_name}"
        sudo cp "${kernel}" "${boot_dir}/${dest_name}"
    fi

    if [[ -n "${initrd}" ]]; then
        [[ ! -f "${initrd}" ]] && lkf_die "initrd not found: ${initrd}"
        local initrd_name="initrd.img${version:+-${version}}"
        lkf_step "Installing initrd -> ${boot_dir}/${initrd_name}"
        sudo cp "${initrd}" "${boot_dir}/${initrd_name}"
    fi

    # Symlinks
    if [[ "${symlinks}" -eq 1 ]]; then
        source "${LKF_ROOT}/core/initrd.sh"
        initrd_cmd_symlink \
            --kernel "${boot_dir}/vmlinuz${version:+-${version}}" \
            ${initrd:+--initrd "${boot_dir}/initrd.img${version:+-${version}}"}
    fi

    # mkinitcpio (Arch Linux)
    if [[ -n "${mkinitcpio_conf}" ]]; then
        lkf_require mkinitcpio
        lkf_step "Running mkinitcpio -p ${mkinitcpio_conf}"
        sudo mkinitcpio -p "${mkinitcpio_conf}"
    fi

    # Bootloader updates
    if [[ "${update_grub}" -eq 1 ]]; then
        if command -v update-grub &>/dev/null; then
            lkf_step "Running update-grub"
            sudo update-grub
        elif command -v grub-mkconfig &>/dev/null; then
            lkf_step "Running grub-mkconfig"
            sudo grub-mkconfig -o /boot/grub/grub.cfg
        else
            lkf_warn "grub update tool not found."
        fi
    fi

    if [[ "${update_bootloader}" -eq 1 ]]; then
        if command -v bootctl &>/dev/null; then
            lkf_step "Running bootctl update"
            sudo bootctl update
        else
            lkf_warn "bootctl not found."
        fi
    fi

    lkf_info "Installation complete."
}
