# lkf profile: server
# Server/headless kernel: no GUI drivers, PREEMPT_NONE, full LTO.

flavor = mainline
arch = x86_64
cc = clang
llvm = true
lto = full
target = server
output = deb
localversion = -lkf-server
