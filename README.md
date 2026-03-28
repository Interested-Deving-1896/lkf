# lkf — Linux Kernel Framework

A distro-agnostic, architecture-agnostic framework for building, compiling,
developing, ricing/remixing, and redistributing Linux kernels.

---

## What it is

`lkf` is a unified shell framework that consolidates the best patterns from 15
independent kernel tooling projects into a single, coherent CLI. It handles the
full kernel lifecycle: source fetch → patch → configure → compile → package →
install → debug → redistribute.

It works on any Linux distro (Debian, Arch, Fedora, Alpine, Void, Gentoo, NixOS…)
and targets any architecture (x86_64, aarch64, arm, riscv64, and more).

---

## Upstream projects incorporated

| Project | Contribution to lkf |
|---|---|
| [ghazzor/Xanmod-Kernel-Builder](https://github.com/ghazzor/Xanmod-Kernel-Builder) | Clang/LLVM CI workflow, LTO config patterns, LLVM apt installer |
| [kodx/symlink-initrd-kernel-in-root](https://github.com/kodx/symlink-initrd-kernel-in-root) | `/vmlinuz` + `/initrd.img` symlink management, pacman hook pattern |
| [rawdaGastan/go-extract-vmlinux](https://github.com/rawdaGastan/go-extract-vmlinux) | vmlinux/vmlinuz extraction logic, ELF validation |
| [elfmaster/kdress](https://github.com/elfmaster/kdress) | vmlinuz → debuggable vmlinux with full ELF symbol table (`lkf extract --symbols`) |
| [eballetbo/unzboot](https://github.com/eballetbo/unzboot) | EFI zboot ARM64 kernel extraction (`lkf extract --type efi-zboot`) |
| [Biswa96/android-kernel-builder](https://github.com/Biswa96/android-kernel-builder) | Android cross-compile pipeline, boot.img repack (`lkf image android-boot`) |
| [AlexanderARodin/LinuxComponentsBuilder](https://github.com/AlexanderARodin/LinuxComponentsBuilder) | kernel + initrd + rootfs + squash pipeline structure |
| [osresearch/linux-builder](https://github.com/osresearch/linux-builder) | Appliance/firmware kernel, unified EFI image (`lkf image efi-unified`), initrd-builder |
| [tsirysndr/vmlinux-builder](https://github.com/tsirysndr/vmlinux-builder) | Multi-arch CI, version normalization, config parse/validate/serialize API |
| [rizalmart/puppy-linux-kernel-maker](https://github.com/rizalmart/puppy-linux-kernel-maker) | AUFS patch workflow, firmware driver packaging, branch-per-version CI pattern |
| [deepseagirl/easylkb](https://github.com/deepseagirl/easylkb) | QEMU+GDB debug environment, debootstrap rootfs, `localyesconfig` guide |
| [limitcool/xm](https://github.com/limitcool/xm) | Cross-compile manager concept (arch × compiler matrix) |
| [masahir0y/kbuild_skeleton](https://github.com/masahir0y/kbuild_skeleton) | Kbuild/Kconfig standalone template, config fragment merging |
| [h0tc0d3/kbuild](https://github.com/h0tc0d3/kbuild) | Flexible CLI flags, DKMS integration, GPG verification, stop-at-stage pipeline |
| [WangNan0/kbuild-standalone](https://github.com/WangNan0/kbuild-standalone) | Standalone kconfig/kbuild as a library, `conf`/`mconf` usage |

---

## Installation

```bash
git clone https://github.com/your-org/lkf
cd lkf
chmod +x lkf.sh tools/extract-vmlinux/extract-vmlinux
sudo make install          # installs to /usr/local/bin/lkf
```

Or run directly without installing:

```bash
./lkf.sh --help
```

To build optional C tools (kdress, unzboot):

```bash
make tools
```

---

## Quick start

```bash
# Build mainline 6.12 for the current host
lkf build --version 6.12 --install-deps

# Build Xanmod with Clang/LLVM + Full LTO
lkf build --version 6.12 --flavor xanmod --llvm --lto full

# Use a named profile
lkf profile use xanmod-desktop --version 6.12

# Cross-compile for aarch64
lkf build --version 6.1 --arch aarch64 --cross aarch64-linux-gnu- --output tar.gz

# Build for Android (boot.img output)
lkf profile use android --version 6.1 --source-dir ~/android-kernel

# Build with AUFS patch (Puppy Linux)
lkf profile use puppy --version 6.12

# Debug kernel in QEMU with GDB
lkf debug --kernel build/vmlinuz-6.12 --rootfs build/rootfs.img --kvm --gdb-init

# Extract vmlinux from a compressed vmlinuz
lkf extract --input /boot/vmlinuz-$(uname -r) --output /tmp/vmlinux

# Extract + instrument with full symbol table (kdress)
lkf extract --input /boot/vmlinuz-$(uname -r) \
            --output /tmp/vmlinux \
            --symbols /boot/System.map-$(uname -r)

# Generate a GitHub Actions CI workflow
lkf ci --arch x86_64,aarch64 --llvm --lto full --release
```

---

## Commands

### `lkf build`

Fetch, configure, patch, and compile a kernel.

```
lkf build --version 6.12 [options]

Key options:
  --flavor      mainline | xanmod | cachyos | zen | rt | android | custom
  --arch        x86_64 | aarch64 | arm | riscv64  [host arch]
  --cross       Cross-compiler prefix (e.g. aarch64-linux-gnu-)
  --llvm        Use Clang/LLVM (LLVM=1 LLVM_IAS=1)
  --lto         none | thin | full
  --config      defconfig | localyesconfig | localmodconfig | <file>
  --patch-set   aufs | rt | xanmod | cachyos
  --output      deb | rpm | pkg.tar.zst | tar.gz | efi-unified | android-boot
  --target      desktop | server | android | embedded | appliance | debug
  --stop-after  download | extract | patch | config | build | install
  --verify-gpg  Verify kernel.org tarball GPG signature
```

### `lkf config`

Manage kernel `.config` files.

```
lkf config generate --source localyesconfig --arch x86_64
lkf config merge    --base .config --fragment debug.config
lkf config validate --file .config --require CONFIG_KVM,CONFIG_VIRTIO
lkf config show     --file .config --category security
lkf config convert  --file .config --format json|toml|yaml
lkf config set      --file .config --option CONFIG_PREEMPT --value y
lkf config diff     --a old.config --b new.config
```

### `lkf patch`

Apply patch sets to a kernel source tree.

```
lkf patch list
lkf patch apply --set aufs --source-dir /path/to/linux
lkf patch apply --file my.patch --source-dir /path/to/linux
```

Built-in patch sets: `aufs`, `rt`, `xanmod`, `cachyos`, `zen4-clang`

### `lkf initrd`

Build initramfs images and manage boot symlinks.

```
lkf initrd build   --config initrd.conf --output build/initrd.cpio.xz
lkf initrd build   --debootstrap --suite bookworm --output rootfs.img
lkf initrd symlink --kernel /boot/vmlinuz-6.12.0 --initrd /boot/initrd.img-6.12.0
lkf initrd inspect --file build/initrd.cpio.xz
```

### `lkf image`

Package kernels into various image formats.

```
lkf image efi-unified  --kernel vmlinuz --initrd initrd.cpio.xz --cmdline cmdline.txt
lkf image android-boot --kernel Image.gz --base-img boot.img --output repacked.img
lkf image firmware     --modules-dir /lib/modules/6.12.0 --output firmware.tar.gz
lkf image tar          --kernel vmlinuz --initrd initrd.cpio.xz
```

### `lkf install`

Install kernel to `/boot` and update bootloader.

```
lkf install --deb linux-image-6.12.0_amd64.deb
lkf install --kernel vmlinuz --version 6.12.0-lkf --symlinks --update-grub
lkf install --kernel vmlinuz --mkinitcpio linux-lkf   # Arch Linux
```

### `lkf debug`

Launch a QEMU+GDB kernel debug environment.

```
lkf debug --kernel build/vmlinuz-6.12 --rootfs build/rootfs.img --kvm
lkf debug --kernel vmlinuz --version 6.12.0 --source-dir ~/linux --gdb-init
lkf debug --kernel vmlinuz --dry-run   # print QEMU command only
```

### `lkf extract`

Extract `vmlinux` from compressed/EFI/Android images.

```
lkf extract --input /boot/vmlinuz-6.12.0 --output /tmp/vmlinux
lkf extract --input /boot/vmlinuz-6.12.0 --output /tmp/vmlinux --symbols /boot/System.map-6.12.0
lkf extract --input kernel.efi --output vmlinux --type efi-zboot
lkf extract --input /tmp/vmlinux --validate
```

### `lkf dkms`

Manage DKMS modules alongside a kernel build.

```
lkf dkms install --module openrazer-driver/3.0.1 --kernel-ver 6.12.0-lkf
lkf dkms sign    --module razerkbd.ko --sign-key mok.key --sign-cert mok.crt
lkf dkms list
```

### `lkf profile`

Named build profiles stored in `~/.config/lkf/profiles/`.

```
lkf profile list
lkf profile show xanmod-desktop
lkf profile create --name my-build --base desktop
lkf profile use xanmod-desktop --version 6.12
```

Built-in profiles: `desktop`, `server`, `android`, `debug`, `embedded`,
`xanmod-desktop`, `puppy`

### `lkf ci`

Generate CI workflow files.

```
lkf ci --arch x86_64,aarch64 --llvm --lto full --release
lkf ci --flavor android --arch aarch64 --output .github/workflows/android.yml
lkf ci --matrix --arch x86_64,aarch64,riscv64
```

### `lkf info`

Print detected host environment.

```
lkf info
```

---

## Project structure

```
lkf/
├── lkf.sh                    # Main entry point
├── Makefile                  # Install, tools, tests
├── core/
│   ├── lib.sh                # Logging, download, GPG, version helpers
│   ├── detect.sh             # Distro/arch/compiler/package-manager detection
│   ├── toolchain.sh          # Dependency installation (all distros)
│   ├── build.sh              # Fetch → patch → configure → compile pipeline
│   ├── config.sh             # .config management (generate/merge/validate/convert)
│   ├── patch.sh              # Patch set application
│   ├── initrd.sh             # initramfs builder + boot symlinks
│   ├── image.sh              # EFI unified, Android boot.img, firmware packaging
│   ├── install.sh            # Kernel installation + bootloader update
│   ├── debug.sh              # QEMU + GDB debug environment
│   ├── extract.sh            # vmlinux extraction (vmlinuz/EFI/Android)
│   ├── dkms.sh               # DKMS module management
│   └── profile.sh            # Named build profile management
├── ci/
│   └── ci.sh                 # GitHub Actions workflow generator
├── config/
│   └── profiles/             # Config fragments per target profile
│       ├── desktop.config
│       ├── server.config
│       ├── debug.config
│       ├── android.config
│       └── embedded.config
├── profiles/                 # Named build profiles (.profile files)
│   ├── desktop.profile
│   ├── server.profile
│   ├── android.profile
│   ├── debug.profile
│   ├── embedded.profile
│   ├── xanmod-desktop.profile
│   └── puppy.profile
├── patches/                  # Local patch sets (place .patch files here)
│   └── <set-name>/           # One directory per named patch set
├── tools/
│   ├── extract-vmlinux/      # Standalone extract-vmlinux script
│   ├── kdress/               # elfmaster/kdress (build separately)
│   └── unzboot/              # eballetbo/unzboot (build separately)
└── tests/
    ├── test_detect.sh
    └── test_config.sh
```

---

## Distro support matrix

| Distro family | Package manager | Tested |
|---|---|---|
| Debian / Ubuntu / Mint / Pop | apt | ✅ |
| Arch / Manjaro / EndeavourOS | pacman | ✅ |
| Fedora / RHEL / Rocky / Alma | dnf | ✅ |
| openSUSE | zypper | ✅ |
| Alpine | apk | ✅ |
| Void | xbps | ✅ |
| Gentoo | emerge | ✅ |
| NixOS | nix | ⚠️ partial |

---

## Architecture support matrix

| Architecture | Kernel ARCH= | Native build | Cross-compile |
|---|---|---|---|
| x86_64 | x86_64 | ✅ | ✅ |
| aarch64 | arm64 | ✅ | ✅ |
| arm (32-bit) | arm | ✅ | ✅ |
| riscv64 | riscv | ✅ | ✅ |
| loongarch64 | loongarch | ✅ | ⚠️ |
| powerpc64le | powerpc | ✅ | ⚠️ |
| s390x | s390 | ✅ | ⚠️ |
| mips | mips | ✅ | ⚠️ |

---

## Adding a custom patch set

1. Create a directory: `patches/<your-set-name>/`
2. Place `.patch` or `.diff` files inside (applied in sort order)
3. Use it: `lkf build --version 6.12 --patch-set <your-set-name>`

---

## Adding a custom profile

```bash
lkf profile create --name my-kernel --base desktop
# Edit ~/.config/lkf/profiles/my-kernel.profile
lkf profile use my-kernel --version 6.12
```

---

## License

Each incorporated project retains its original license. The lkf framework
itself is released under GPL-2.0.

See `tools/kdress/README.md` and `tools/unzboot/README.md` for the licenses
of those optional compiled tools.
