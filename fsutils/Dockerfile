# fsutils packages Alpine's own precompiled mkfs.vfat (dosfstools) and
# mkfs.xfs (xfsprogs), dynamically linked against Alpine's own musl, for
# the invarios appliance rootfs. This is a deliberate, temporary
# shortcut: unlike kernel/ and systemd-boot/, nothing here is fetched
# from its own upstream or GPG-verified -- apk's own signature check
# against Alpine's repo keys is the trust boundary instead. Building
# musl/xfsprogs/dosfstools from their own verified upstream source, the
# same way kernel/ and systemd-boot/ already are, replaces this package
# entirely; it's tracked debt, not abandoned.
FROM alpine:3.24 AS builder

# mkfs.vfat is a symlink to mkfs.fat in the same package -- both are
# staged so the symlink resolves. Every shared library each binary
# links against (per `ldd`) is copied alongside it, dereferencing
# apk's version-suffixed symlinks (e.g. libblkid.so.1 -> libblkid.so.1.1.0)
# with `cp -L` so /out ships plain regular files at the exact paths
# their ELF DT_NEEDED entries expect -- no ldconfig/ld.so.cache exists
# in the initramfs to resolve indirection at runtime.
RUN apk add --no-cache xfsprogs dosfstools \
    && mkdir -p /out/sbin /out/lib /out/usr/lib \
    && cp -L /sbin/mkfs.fat /out/sbin/mkfs.fat \
    && ln -s mkfs.fat /out/sbin/mkfs.vfat \
    && cp -L /sbin/mkfs.xfs /out/sbin/mkfs.xfs \
    && cp -L /lib/ld-musl-*.so.1 /out/lib/ \
    && cp -L \
        /usr/lib/libblkid.so.1 \
        /usr/lib/libuuid.so.1 \
        /usr/lib/libinih.so.0 \
        /usr/lib/liburcu.so.8 \
        /usr/lib/libeconf.so.0 \
        /out/usr/lib/

FROM scratch
COPY --from=builder /out/ /
