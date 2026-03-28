# unzboot tool

Source: https://github.com/eballetbo/unzboot

Extracts and decompresses a Linux kernel image from an EFI zboot application.
Designed for ARM64 kernels embedded in EFI zboot images.

## Build

```bash
git clone https://github.com/eballetbo/unzboot /tmp/unzboot
cd /tmp/unzboot
meson setup build
meson compile -C build
cp build/unzboot /path/to/lkf/tools/unzboot/unzboot
```

## Dependencies

- gcc, meson, ninja
- glib-2.0, zlib, libzstd

```bash
# Debian/Ubuntu
sudo apt-get install meson ninja-build libglib2.0-dev zlib1g-dev libzstd-dev

# Fedora
sudo dnf install meson ninja-build glib2-devel zlib-devel libzstd-devel

# Alpine
sudo apk add meson gcc glib-dev musl-dev zstd-libs
```

## Usage via lkf

```bash
lkf extract --input kernel.efi --output vmlinux --type efi-zboot
```
