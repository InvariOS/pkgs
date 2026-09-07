#!/usr/bin/env bash
#
# Fetches a GPG-verified systemd release tag and builds only the
# systemd-boot bootloader and its EFI stub from it. Every other systemd
# component is disabled at the meson level, so this never depends on
# daemon-only pieces (logind, networkd, polkit, ...).
#
# Runs natively on the target arch (invoked from a single-platform
# buildx build), so meson's own host-arch detection picks the right EFI
# arch (x64 vs aa64) without a cross file. Produces /out/systemd-boot.efi
# and /out/boot.efi.stub with arch-neutral names.

set -euo pipefail

SYSTEMD_VERSION="${SYSTEMD_VERSION:?SYSTEMD_VERSION is required}"
SYSTEMD_TAG="v${SYSTEMD_VERSION}"
SYSTEMD_REPO_URL="https://github.com/systemd/systemd.git"

# systemd's release-signing keys. A tag signed by anyone else is
# rejected below.
SYSTEMD_SIGNERS=(
    "AC24AAC7DDC420F18ECA6B91286BF7EFCD77241E" # Luca Boccassi (signing subkey)
    "5C251B5FC54EB2F80F407AAAC54CA336CFEB557E" # Zbigniew Jędrzejewski-Szmek
)

log() { printf '[systemd-boot] %s\n' "$*"; }
die() { printf '[error] %s\n' "$*" >&2; exit 1; }

export GNUPGHOME="/tmp/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 0700 "${GNUPGHOME}"

log "fetching systemd ${SYSTEMD_TAG} source"
git clone --depth 1 --branch "${SYSTEMD_TAG}" "${SYSTEMD_REPO_URL}" src
cd src

log "verifying systemd ${SYSTEMD_TAG} tag signature"
gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "${SYSTEMD_SIGNERS[@]}"

status="$(git verify-tag --raw "${SYSTEMD_TAG}" 2>&1)"

if grep -qE '^\[GNUPG:\] (REVKEYSIG|EXPKEYSIG|EXPSIG) ' <<< "${status}"; then
    die "systemd tag signature uses a revoked or expired key/signature"
fi

signer="$(awk '/^\[GNUPG:\] VALIDSIG / { print $3; exit }' <<< "${status}")"
[[ -n "${signer}" ]] || die "systemd tag signature verification failed"

verified=0
for allowed in "${SYSTEMD_SIGNERS[@]}"; do
    if [[ "${signer}" == "${allowed}" ]]; then
        verified=1
        break
    fi
done
[[ "${verified}" == 1 ]] || die "systemd tag signed by untrusted key: ${signer}"
log "verified systemd signer: ${signer}"

log "building systemd-boot ${SYSTEMD_TAG}"

# This package ships only the EFI bootloader and its stub, not a full
# systemd install, so every other component is disabled here. Otherwise
# the meson configure step would go looking for daemon-only
# dependencies (logind, networkd, polkit, ...) that have no reason to
# exist in a scratch image containing two EFI binaries.
meson setup \
    --buildtype=release \
    --wrap-mode=nodownload \
    -Dstrip=true \
    -Dlibc=musl \
    -Dversion-tag="${SYSTEMD_VERSION}-invarios" \
    -Dsbat-distro=invarios \
    -Dsbat-distro-summary="InvariOS" \
    -Dsbat-distro-pkgname=systemd-boot \
    -Dsbat-distro-version="${SYSTEMD_VERSION}" \
    -Dsbat-distro-url="https://github.com/InvariOS/pkgs" \
    -Dadm-group=false \
    -Danalyze=false \
    -Dbacklight=false \
    -Dbinfmt=false \
    -Dbootloader=enabled \
    -Dcompat-mutable-uid-boundaries=false \
    -Dcoredump=false \
    -Ddns-over-tls=false \
    -Defi=true \
    -Denvironment-d=false \
    -Dfexecve=false \
    -Dfirstboot=false \
    -Dfirst-boot-full-preset=false \
    -Dgshadow=false \
    -Dhibernate=false \
    -Dhomed=disabled \
    -Dhostnamed=false \
    -Dhwdb=false \
    -Didn=false \
    -Dima=false \
    -Dimportd=disabled \
    -Dinitrd=false \
    -Dkernel-install=false \
    -Dldconfig=false \
    -Dlocaled=false \
    -Dlogind=false \
    -Dmachined=false \
    -Dnetworkd=false \
    -Dnss-myhostname=false \
    -Dnss-mymachines=disabled \
    -Dnss-resolve=disabled \
    -Dnss-systemd=false \
    -Doomd=false \
    -Dpolkit=disabled \
    -Dportabled=false \
    -Dpstore=false \
    -Dquotacheck=false \
    -Drandomseed=false \
    -Dremote=disabled \
    -Drepart=disabled \
    -Dresolve=false \
    -Drfkill=false \
    -Dsmack=false \
    -Dstoragetm=false \
    -Dsysext=false \
    -Dsysupdate=disabled \
    -Dsysusers=false \
    -Dtimedated=false \
    -Dtimesyncd=false \
    -Dtmpfiles=false \
    -Dtpm=false \
    -Dukify=disabled \
    -Durlify=false \
    -Duserdb=false \
    -Dutmp=false \
    -Dvconsole=false \
    -Dvmspawn=disabled \
    -Dwheel-group=false \
    -Dxdg-autostart=false \
    build

meson compile -C build systemd-boot

mkdir -p /out

efi_bin="$(find build/src/boot -maxdepth 1 -name 'systemd-boot*.efi' -print -quit)"
stub_bin="$(find build/src/boot -maxdepth 1 -name 'linux*.efi.stub' -print -quit)"

[[ -n "${efi_bin}" ]] || die "systemd-boot build did not produce a systemd-boot*.efi binary"
[[ -n "${stub_bin}" ]] || die "systemd-boot build did not produce a linux*.efi.stub binary"

install -m 0644 "${efi_bin}" /out/systemd-boot.efi
install -m 0644 "${stub_bin}" /out/boot.efi.stub

log "systemd-boot binary:"
file /out/systemd-boot.efi

log "EFI stub binary:"
file /out/boot.efi.stub
