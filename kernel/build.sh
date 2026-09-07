#!/usr/bin/env bash
#
# Fetches, GPG-verifies, and builds the Linux kernel for TARGETARCH.
# Produces /out/vmlinuz (a PE/COFF EFI executable via CONFIG_EFI_STUB,
# on both x86_64 and arm64) and /out/kernel.config.

set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:?KERNEL_VERSION is required}"
TARGETARCH="${TARGETARCH:?TARGETARCH is required}"

case "${TARGETARCH}" in
    amd64) ARCH=x86_64 ;;
    arm64) ARCH=arm64 ;;
    *) echo "[error] unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac

KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_ARCHIVE="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x"

# kernel.org's own release signers. A tarball signed by anyone else is
# rejected below.
KERNEL_SIGNERS=(
    "ABAF11C65A2970B130ABE3C479BE3E4300411886" # Linus Torvalds
    "647F28654894E3BD457199BE38DBBDC86092693E" # Greg Kroah-Hartman
    "E27E5D8A3403A2EF66873BBCDEA66FF797772CDC" # Sasha Levin
    "AC2B29BD34A6AFDDB3F68F35E7BFC8EC95861109" # Ben Hutchings
)

log() { printf '[kernel] %s\n' "$*"; }
die() { printf '[error] %s\n' "$*" >&2; exit 1; }

export GNUPGHOME="/tmp/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 0700 "${GNUPGHOME}"

log "fetching kernel.org developer keyring"
curl -fL -o /tmp/keyring.gpg https://www.kernel.org/pub/site/keyring.gpg
gpg --batch --import /tmp/keyring.gpg

log "fetching Linux ${KERNEL_VERSION}"
curl -fL -o "${KERNEL_ARCHIVE}" "${KERNEL_BASE_URL}/${KERNEL_ARCHIVE}"
curl -fL -o "${KERNEL_ARCHIVE%.xz}.sign" "${KERNEL_BASE_URL}/${KERNEL_ARCHIVE%.xz}.sign"

log "verifying Linux ${KERNEL_VERSION} signature"
status="$(
    xz -cd "${KERNEL_ARCHIVE}" \
        | gpg --batch --status-fd=1 --verify "${KERNEL_ARCHIVE%.xz}.sign" - 2>/dev/null
)"

if grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG|EXPSIG) ' <<< "${status}"; then
    die "kernel signature uses a revoked or expired key/signature"
fi

signer="$(awk '/^\[GNUPG:\] VALIDSIG / { print $3; exit }' <<< "${status}")"
[[ -n "${signer}" ]] || die "kernel signature verification failed"

verified=0
for allowed in "${KERNEL_SIGNERS[@]}"; do
    if [[ "${signer}" == "${allowed}" ]]; then
        verified=1
        break
    fi
done
[[ "${verified}" == 1 ]] || die "kernel signed by untrusted key: ${signer}"
log "verified kernel signer: ${signer}"

log "extracting Linux ${KERNEL_VERSION}"
mkdir -p src
tar -xJf "${KERNEL_ARCHIVE}" -C src --strip-components=1
cd src

log "configuring kernel for ${ARCH}"
make ARCH="${ARCH}" defconfig

# Virtio-rng (HW_RANDOM_VIRTIO) lets a hypervisor-provided entropy device
# credit the kernel's CRNG immediately. ARCH_RANDOM covers the CPU's own
# hardware RNG (RDRAND/RDSEED on x86_64, RNDR on arm64). Without one of
# these, CRNG initialization can block on boot-time entropy collection
# for long enough that early userspace operations relying on
# getrandom() (e.g. DHCP) time out.
./scripts/config \
    --enable BLK_DEV_INITRD \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
    --enable EFI \
    --enable EFI_STUB \
    --enable PROC_FS \
    --enable SYSFS \
    --enable TMPFS \
    --enable NET \
    --enable INET \
    --enable VIRTIO \
    --enable VIRTIO_PCI \
    --enable VIRTIO_NET \
    --enable VIRTIO_BLK \
    --enable VIRTIO_CONSOLE \
    --enable ARCH_RANDOM \
    --enable HW_RANDOM \
    --enable HW_RANDOM_VIRTIO \
    --enable SERIAL_8250 \
    --enable SERIAL_8250_CONSOLE \
    --enable DRM \
    --enable DRM_FBDEV_EMULATION \
    --enable FB \
    --enable FRAMEBUFFER_CONSOLE \
    --enable FRAMEBUFFER_CONSOLE_DETECT_PRIMARY \
    --enable DRM_SIMPLEDRM \
    --enable DRM_EFIDRM \
    --enable DRM_VIRTIO_GPU

make ARCH="${ARCH}" olddefconfig

log "building kernel for ${ARCH}"

# Named explicitly rather than relying on the default "all" target: on
# arm64 "all" builds Image.gz, which depends on (and therefore also
# produces) Image, but pays for a gzip pass we never use since we ship
# the uncompressed, EFI-bootable Image directly.
case "${ARCH}" in
    x86_64) KERNEL_TARGET=bzImage ;;
    arm64) KERNEL_TARGET=Image ;;
esac

make ARCH="${ARCH}" -j"$(nproc)" "${KERNEL_TARGET}"

mkdir -p /out

case "${ARCH}" in
    x86_64)
        install -m 0644 arch/x86/boot/bzImage /out/vmlinuz
        ;;
    arm64)
        install -m 0644 arch/arm64/boot/Image /out/vmlinuz
        ;;
esac

install -m 0644 .config /out/kernel.config

log "kernel built:"
file /out/vmlinuz
ls -lh /out/vmlinuz
