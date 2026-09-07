FROM alpine:3.24 AS builder

RUN apk add --no-cache \
    bash \
    bc \
    bison \
    build-base \
    curl \
    elfutils-dev \
    file \
    findutils \
    flex \
    gnupg \
    linux-headers \
    ncurses-dev \
    openssl-dev \
    perl \
    tar \
    xz

ARG KERNEL_VERSION=6.18.49
ARG TARGETARCH

ENV KERNEL_VERSION=${KERNEL_VERSION} \
    TARGETARCH=${TARGETARCH}

WORKDIR /work
COPY build.sh .
RUN bash build.sh

FROM scratch
COPY --from=builder /out/ /
