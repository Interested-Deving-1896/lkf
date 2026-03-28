# lkf profile: xanmod-desktop
# Xanmod kernel with Clang/LLVM + Full LTO for desktop use.
# Inspired by ghazzor/Xanmod-Kernel-Builder.

flavor = xanmod
arch = x86_64
cc = clang
llvm = true
llvm_version = 19
lto = full
target = desktop
output = deb
localversion = -xanmod-clang
