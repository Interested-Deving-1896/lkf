# patches/

Patch sets applied by `lkf build` before compilation.

## Directory layout

```
patches/
  aufs/          AUFS (Another Union File System) patches
  rt/            PREEMPT_RT real-time patches
  xanmod/        XanMod kernel patches
  cachyos/       CachyOS scheduler and optimization patches
  custom/        Local patches (not fetched automatically)
  series         Optional: ordered list of patches to apply (quilt format)
```

Each subdirectory holds `.patch` files named after the kernel version they
target, e.g. `aufs6.6.patch`, `patch-6.6.30-rt30.patch`.

## Fetching patches

Run the fetch script to download patches for a specific kernel version:

```sh
lkf patch fetch --version 6.6.30
# or fetch a specific set only:
lkf patch fetch --version 6.6.30 --set rt
lkf patch fetch --version 6.6.30 --set cachyos
```

The script is `patches/fetch.sh` and can also be called directly.

## Applying patches

`lkf build` applies patches automatically during the `patch` stage.
To apply manually:

```sh
lkf patch apply --version 6.6.30 --set rt
```

To skip patching entirely:

```sh
lkf build --no-patch
```

## Adding custom patches

Drop `.patch` files into `patches/custom/`. They are applied after all
upstream patch sets, in lexicographic order.

## Supported patch sets

| Set      | Source                                      | Notes                        |
|----------|---------------------------------------------|------------------------------|
| aufs     | https://github.com/sfjro/aufs-standalone    | Union filesystem overlay     |
| rt       | https://cdn.kernel.org/pub/linux/kernel/projects/rt/ | PREEMPT_RT       |
| xanmod   | https://github.com/xanmod/linux-patches     | Latency + scheduler tweaks   |
| cachyos  | https://github.com/CachyOS/kernel-patches   | BORE/EEVDF scheduler patches |
| tkg      | https://github.com/Frogging-Family/linux-tkg | Gaming/desktop: BORE, BMQ, PDS, NTsync, Clear Linux, ACS override, OpenRGB |

### tkg patch files (6.12 example)

| File                                    | Controlled by          | Purpose                              |
|-----------------------------------------|------------------------|--------------------------------------|
| `0001-bore.patch`                       | `_cpusched=bore`       | BORE scheduler                       |
| `0002-clear-patches.patch`              | `_clear_patches=true`  | Clear Linux performance patches      |
| `0003-glitched-base.patch`              | always                 | Base TkG tweaks (mm, sched, net)     |
| `0003-glitched-cfs.patch`              | `_cpusched=cfs`        | CFS/EEVDF glitched additions         |
| `0003-glitched-eevdf-additions.patch`   | `_cpusched=eevdf`      | EEVDF extra tweaks                   |
| `0005-glitched-pds.patch`              | `_cpusched=pds`        | PDS scheduler (Project C)            |
| `0006-add-acs-overrides_iommu.patch`    | `_acs_override=true`   | ACS IOMMU override for GPU passthrough |
| `0007-v*.ntsync.patch`                 | `_ntsync=true`         | NTsync (Wine/Proton performance)     |
| `0007-v*.fsync_legacy*.patch`          | `_fsync_legacy=true`   | Fsync legacy via futex_waitv         |
| `0009-prjc.patch`                      | `_cpusched=bmq/pds`    | Project C base (BMQ/PDS)             |
| `0009-glitched-bmq.patch`              | `_cpusched=bmq`        | BMQ scheduler (Project C)            |
| `0012-misc-additions.patch`             | always                 | Miscellaneous additions              |
| `0013-optimize_harder_O3.patch`         | `_per_cpu_arch`        | O3 + per-CPU-arch optimizations      |
| `0014-OpenRGB.patch`                    | `_openrgb=true`        | OpenRGB kernel support               |
