# kdress tool

Source: https://github.com/elfmaster/kdress

This tool transforms a compressed `vmlinuz` into a fully debuggable `vmlinux`
with a complete ELF symbol table, usable with `/proc/kcore` for live kernel
debugging and forensics without recompiling with debug symbols.

## Build

```bash
git clone https://github.com/elfmaster/kdress /tmp/kdress
cd /tmp/kdress
make
cp kdress /path/to/lkf/tools/kdress/kdress
```

## Usage via lkf

```bash
lkf extract --input /boot/vmlinuz-$(uname -r) \
            --output /tmp/vmlinux \
            --symbols /boot/System.map-$(uname -r)
```

The `lkf extract` command will automatically use this binary if present.
