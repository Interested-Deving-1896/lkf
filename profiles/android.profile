# lkf profile: android
# Android kernel cross-compile for aarch64.
# Inspired by Biswa96/android-kernel-builder.

flavor = android
arch = aarch64
cc = clang
llvm = true
lto = thin
target = android
output = android-boot
localversion = -lkf-android
