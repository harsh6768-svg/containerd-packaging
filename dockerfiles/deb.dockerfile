#   Copyright 2018-2020 Docker Inc.

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

ARG BUILD_IMAGE=ubuntu:bionic
ARG GOLANG_IMAGE=golang:latest

# Install golang from the official image, since the package managed
# one probably is too old and ppa's don't cover all distros
FROM ${GOLANG_IMAGE} AS golang

FROM golang AS go-md2man
ARG GOPROXY=direct
ARG GO111MODULE=on
ARG MD2MAN_VERSION=v2.0.0
RUN go get github.com/cpuguy83/go-md2man/v2/@${MD2MAN_VERSION}

FROM ${BUILD_IMAGE} AS distro-image

FROM distro-image AS build-env
RUN mkdir -p /go
ENV GOPATH=/go
ENV PATH="${PATH}:/usr/local/go/bin:${GOPATH}/bin"
ENV IMPORT_PATH=github.com/containerd/containerd
ENV GO_SRC_PATH="/go/src/${IMPORT_PATH}"
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /root/containerd

# Install some pre-reqs
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    devscripts \
    equivs \
    git \
    lsb-release \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install build dependencies and build scripts
COPY --from=go-md2man /go/bin/go-md2man /go/bin/go-md2man
COPY --from=golang    /usr/local/go/    /usr/local/go/
COPY debian/ debian/
RUN apt-get update \
 && mk-build-deps -t "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y" -i debian/control \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/build-deb    /root/
COPY scripts/.helpers     /root/

ARG PACKAGE
ENV PACKAGE=${PACKAGE:-containerd.io}

FROM build-env AS build-packages
RUN mkdir -p /archive /build
COPY common/containerd.service common/containerd.toml /root/common/
COPY src /go/src
ARG CREATE_ARCHIVE
RUN /root/build-deb
ARG UID=0
ARG GID=0
RUN chown -R ${UID}:${GID} /archive /build

FROM scratch AS packages
COPY --from=build-packages /archive /archive
COPY --from=build-packages /build   /build

# This stage is mainly for debugging (running the build interactively with mounted source)
FROM build-env AS runtime
COPY common/containerd.service common/containerd.toml /root/common/
