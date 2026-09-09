#!/usr/bin/env bash
#
# Fetches curl.se's dated PEM conversion of Mozilla's CA root
# certificate store and verifies it against a pinned sha256. curl.se
# doesn't publish a signature for this file, so a pinned content hash,
# checked here against the exact bytes fetched, is the trust boundary
# instead.
#
# Produces /out/etc/ssl/certs/ca-certificates.crt.

set -euo pipefail

CA_CERTIFICATES_VERSION="${CA_CERTIFICATES_VERSION:?CA_CERTIFICATES_VERSION is required}"
CA_CERTIFICATES_SHA256="${CA_CERTIFICATES_SHA256:?CA_CERTIFICATES_SHA256 is required}"

CACERT_FILE="cacert-${CA_CERTIFICATES_VERSION}.pem"
CACERT_URL="https://curl.se/ca/${CACERT_FILE}"

log() { printf '[ca-certificates] %s\n' "$*"; }
die() { printf '[error] %s\n' "$*" >&2; exit 1; }

log "fetching ${CACERT_FILE}"
curl -fL -o "${CACERT_FILE}" "${CACERT_URL}"

log "verifying ${CACERT_FILE} checksum"
echo "${CA_CERTIFICATES_SHA256}  ${CACERT_FILE}" | sha256sum -c - \
    || die "checksum mismatch for ${CACERT_FILE}"

mkdir -p /out/etc/ssl/certs
install -m 0644 "${CACERT_FILE}" /out/etc/ssl/certs/ca-certificates.crt

log "installed CA bundle:"
wc -l /out/etc/ssl/certs/ca-certificates.crt
