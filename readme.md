# InvariOS Packages

Build definitions for InvariOS's boot components, published as scratch OCI
images to `ghcr.io/invarios/pkgs/<package>`.

## Packages

| Package | Image | Produces |
| --- | --- | --- |
| [`kernel/`](kernel) | `ghcr.io/invarios/pkgs/kernel` | `/vmlinuz`, `/kernel.config` |
| [`systemd-boot/`](systemd-boot) | `ghcr.io/invarios/pkgs/systemd-boot` | `/systemd-boot.efi`, `/boot.efi.stub` |

Each package directory is self-contained:

- `Dockerfile` -- multi-stage build ending in `FROM scratch`, so the
  published image contains only the built artifacts.
- `build.sh` -- fetches the pinned upstream release, verifies its GPG
  signature against a hardcoded signer allow-list, and builds it.
- `VERSION` -- the pinned upstream version. CI reads this file to tag
  the published image; it's the single source of truth for version
  bumps.

## Tagging

Images are tagged `<version>-<arch>`, e.g. `6.18.49-amd64`,
`6.18.49-arm64`. Each arch is a separate single-platform image built
natively (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`) rather
than one multi-platform manifest, so builds run in parallel without
QEMU emulation.

## CI

Each package has its own workflow (`.github/workflows/kernel.yml`,
`.github/workflows/systemd-boot.yml`), triggered only by changes under
its own directory. Pull requests build (but don't push) both arches;
pushes to `main` build and push.

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
