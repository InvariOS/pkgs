FROM alpine:3.24 AS builder

RUN apk add --no-cache \
    bash \
    build-base \
    curl \
    file \
    findutils \
    git \
    gnupg \
    gperf \
    libcap-dev \
    libucontext-dev \
    meson \
    musl-libintl \
    ninja \
    pkgconf \
    py3-elftools \
    py3-jinja2 \
    util-linux-dev

ARG SYSTEMD_VERSION=261.2

ENV SYSTEMD_VERSION=${SYSTEMD_VERSION}

WORKDIR /work
COPY build.sh .
RUN bash build.sh

FROM scratch
COPY --from=builder /out/ /
