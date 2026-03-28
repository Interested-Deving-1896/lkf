# lkf profile: puppy
# Puppy Linux kernel with AUFS patch and firmware drivers.
# Inspired by rizalmart/puppy-linux-kernel-maker.

flavor = mainline
arch = x86_64
cc = gcc
llvm = false
lto = none
target = desktop
output = tar.gz
patch_set = aufs
localversion = -puppy
