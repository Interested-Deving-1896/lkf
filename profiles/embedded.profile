# lkf profile: embedded
# Minimal kernel for firmware/appliance targets.
# Inspired by osresearch/linux-builder appliance use case.

flavor = mainline
arch = x86_64
cc = gcc
llvm = false
lto = none
target = embedded
output = efi-unified
localversion = -lkf-embedded
