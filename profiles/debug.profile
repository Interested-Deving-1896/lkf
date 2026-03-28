# lkf profile: debug
# Kernel for debugging with KASAN, UBSAN, LOCKDEP, GDB support.
# Inspired by deepseagirl/easylkb.

flavor = mainline
arch = x86_64
cc = gcc
llvm = false
lto = none
target = debug
output = tar.gz
localversion = -lkf-debug
