# InvariOS Packages

Build definitions for InvariOS's boot components, published as scratch OCI
images to `ghcr.io/invarios/<package>`.

## Packages

| Package | Image | Produces |
| --- | --- | --- |
| [`kernel/`](kernel) | `ghcr.io/invarios/kernel` | `/vmlinuz`, `/kernel.config` |
| [`systemd-boot/`](systemd-boot) | `ghcr.io/invarios/systemd-boot` | `/systemd-boot.efi`, `/boot.efi.stub` |
| [`fsutils/`](fsutils) | `ghcr.io/invarios/fsutils` | `/sbin/mkfs.vfat`, `/sbin/mkfs.xfs` + their runtime `.so` deps |
| [`ca-certificates/`](ca-certificates) | `ghcr.io/invarios/ca-certificates` | `/etc/ssl/certs/ca-certificates.crt` |

`kernel/` and `systemd-boot/` are self-contained in the strict sense:

- `Dockerfile` -- multi-stage build ending in `FROM scratch`, so the
  published image contains only the built artifacts.
- `build.sh` -- fetches the pinned upstream release, verifies its GPG
  signature against a hardcoded signer allow-list, and builds it.
- `VERSION` -- the pinned upstream version. CI reads this file to tag
  the published image; it's the single source of truth for version
  bumps.

`fsutils/` is a deliberate, temporary exception to that pattern: instead
of fetching its own upstream source and verifying a GPG signature, its
single-stage `Dockerfile` runs `apk add xfsprogs dosfstools` against a
pinned Alpine base image and copies the resulting binaries plus their
runtime `.so` dependencies (Alpine's own musl among them) straight out
of the `FROM scratch` final stage -- `apk`'s own signature check against
Alpine's repo keys is the trust boundary, not our own verification.
This exists so [invarios](https://github.com/invarios/invarios)'s
install sequence can format the target disk's ESP/STATE/DATA partitions
at runtime without vendoring a full from-source musl/xfsprogs/dosfstools
toolchain yet; replacing it with one (matching the `kernel`/
`systemd-boot` pattern above) is tracked debt, not abandoned.

`ca-certificates/` has its own pinned upstream version, verified before
use: its `build.sh` fetches curl.se's dated PEM conversion of Mozilla's
CA root store and checks it against the `SHA256` file's pinned value,
since curl.se doesn't publish its own signature for that file.
`VERSION` holds curl.se's date stamp (e.g. `2026-08-13`); both files
are bumped together when the CA bundle is
updated.

## Toolchain images

| Image | Image | Contains |
| --- | --- | --- |
| [`builder/`](builder) | `ghcr.io/invarios/builder` | Go toolchain plus `dosfstools`/`mtools`/`xorriso`, used by the [invarios](https://github.com/invarios/invarios) `Makefile` to build/run the appliance image builder |

Unlike the package images above, `builder/` is a plain single-stage
image (not `FROM scratch`, no `VERSION`/`build.sh`) and is published as
a single multi-platform manifest tagged `:main`, built with QEMU
emulation for the non-native arch rather than the native per-arch
matrix used for `kernel`/`systemd-boot`.

## Tagging

Package images (`kernel`, `systemd-boot`) are tagged `<version>-<arch>`,
e.g. `6.18.49-amd64`, `6.18.49-arm64`. Each arch is a separate
single-platform image built natively (amd64 on `ubuntu-latest`, arm64 on
`ubuntu-24.04-arm`) rather than one multi-platform manifest, so builds
run in parallel without QEMU emulation.

The `builder` toolchain image is tagged `:main` (plus `:sha-<sha>`) as a
single multi-platform (`linux/amd64,linux/arm64`) manifest, built with
QEMU emulation for the non-native arch.

`fsutils` follows the same `:main` (plus `:sha-<sha>`) tagging as
`builder`, for the same reason: it has no independent upstream version
of its own to pin -- it just tracks whatever the pinned Alpine base
image's `xfsprogs`/`dosfstools` packages currently resolve to.

`ca-certificates` is tagged `<VERSION>` (curl.se's date stamp, e.g.
`2026-08-13`), `:main`, and `:sha-<sha>`. `:main` always points at
whatever bundle is currently pinned on the default branch, so a
consumer that wants the current CA bundle without tracking `VERSION`
bumps itself can pull it directly; `<VERSION>` exists for a build that
needs to pin an exact bundle instead. It's published as a single
multi-platform manifest rather than a separate build per arch, since
the pinned PEM itself doesn't depend on architecture.

## CI

Each package has its own workflow (`.github/workflows/kernel.yml`,
`.github/workflows/systemd-boot.yml`), triggered only by changes under
its own directory. Pull requests build (but don't push) both arches;
pushes to `main` build and push.

`builder` has its own workflow (`.github/workflows/builder.yml`),
triggered only by changes under `builder/`, which builds and pushes the
multi-arch manifest directly with `docker/build-push-action`. Pull
requests build (but don't push); pushes to `main` build and push.

`fsutils` has its own workflow (`.github/workflows/fsutils.yml`),
triggered only by changes under `fsutils/`, structured the same way as
`builder`.

`ca-certificates` has its own workflow
(`.github/workflows/ca-certificates.yml`), triggered only by changes
under `ca-certificates/`. It builds the same multi-platform manifest on
every run (pull requests included) but only pushes it on `main`,
reading `VERSION`/`SHA256` to pass as build args.

## Building locally

```sh
cd kernel # or systemd-boot
docker build \
  --platform linux/amd64 \
  --build-arg KERNEL_VERSION=$(cat VERSION) \
  -t invarios-pkgs-kernel:$(cat VERSION)-amd64 \
  .
```

(Swap `KERNEL_VERSION` for `SYSTEMD_VERSION` and the image name when
building `systemd-boot/`.)

```sh
cd builder
docker build -t invarios-pkgs-builder:main .
```

```sh
cd fsutils
docker build -t invarios-pkgs-fsutils:main .
```

```sh
cd ca-certificates
docker build \
  --build-arg CA_CERTIFICATES_VERSION=$(cat VERSION) \
  --build-arg CA_CERTIFICATES_SHA256=$(cat SHA256) \
  -t invarios-pkgs-ca-certificates:$(cat VERSION) \
  .
```
