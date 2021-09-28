FROM ubuntu:hirsute as build

ARG OS_ARCH="amd64"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update
RUN apt-get -y install golang-go git wget curl build-essential devscripts debhelper libseccomp-dev
RUN apt-get -y install libapparmor-dev libassuan-dev libbtrfs-dev libc6-dev libdevmapper-dev libglib2.0-dev libgpgme-dev libgpg-error-dev libprotobuf-dev libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev pkg-config


SHELL ["/usr/bin/bash", "-e", "-c"]

# See https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#download-and-install-worker-binaries


# Build runc from source
WORKDIR /src
ARG RUNC_VERSION="v1.0.2"
RUN git clone --single-branch --branch=${RUNC_VERSION} https://github.com/opencontainers/runc /src/runc
WORKDIR /src/runc
RUN make

# Build conmon from source
WORKDIR /src
ARG CONMON_VERSION="v2.0.30"
RUN git clone --single-branch --branch=${CONMON_VERSION} https://github.com/containers/conmon.git /src/conmon
WORKDIR /src/conmon
RUN make


# Build podman from source.
WORKDIR /src
ARG PODMAN_VERSION="v3.3.1"
RUN git clone --single-branch --branch=${PODMAN_VERSION} https://github.com/containers/podman.git /src/podman
WORKDIR /src/podman
RUN make BUILDTAGS="selinux seccomp systemd"


# Build containerd from source
WORKDIR /src
ARG CONTAINERD_VERSION="v1.5.5"
RUN git clone --depth=1 --single-branch --branch=${CONTAINERD_VERSION} https://github.com/containerd/containerd /src/containerd
WORKDIR /src/containerd
RUN BUILDTAGS=no_btrfs make

# Build crictl from source cri-tools

# Build containerd from source
WORKDIR /src
ARG CRI_TOOLS_VERSION="v1.22.0"
RUN git clone --depth=1 --single-branch --branch=${CRI_TOOLS_VERSION} https://github.com/kubernetes-sigs/cri-tools /src/cri-tools
WORKDIR /src/cri-tools
RUN make

# Prepare the results in /out,
WORKDIR /out/usr/sbin
RUN cp -v /src/runc/runc .
WORKDIR /out/usr/bin
RUN cp -v /src/cri-tools/build/bin/crictl crictl-latest # avoid conflict with kubeadm-required cri-tools which contrains an old crictl
RUN cp -v /src/cri-tools/build/bin/critest .
RUN cp -v /src/containerd/bin/* .
RUN cp -v /src/podman/bin/podman .
RUN cp -v /src/conmon/bin/conmon .

# add podman default configs
WORKDIR /out/etc/containers
RUN curl -L -o /out/etc/containers/registries.conf https://src.fedoraproject.org/rpms/containers-common/raw/main/f/registries.conf
RUN curl -L -o /out/etc/containers/policy.json https://src.fedoraproject.org/rpms/containers-common/raw/main/f/default-policy.json

# Prepare debian binary package
WORKDIR /pkg/src
ADD debian /pkg/src/debian
RUN cp -rvp /out/* /pkg/src/
# Create the .install file with the binaries to be installed, without leading slash
RUN find /out -type f | sed -e 's/^\/out\///g' > debian/k8s-worker-containerd.install

# Create the "Architecture: amd64" field in control
RUN echo "Architecture: ${OS_ARCH}" >> /pkg/src/debian/control
RUN cat /pkg/src/debian/control

# Create the Changelog, fake. The atrocities we do in dockerfiles.
ARG PACKAGE_VERSION="20210928"
RUN echo "k8s-worker-containerd (${PACKAGE_VERSION}) stable; urgency=medium" >> /pkg/src/debian/changelog
RUN echo "" >> /pkg/src/debian/changelog
RUN echo "  * Not a real changelog. Sorry." >> /pkg/src/debian/changelog
RUN echo "" >> /pkg/src/debian/changelog
RUN echo " -- Ricardo Pardini <ricardo@pardini.net>  Wed, 15 Sep 2021 14:18:33 +0200" >> /pkg/src/debian/changelog
RUN cat /pkg/src/debian/changelog


# Build the package, don't sign it, don't lint it
WORKDIR /pkg/src
RUN debuild --no-lintian --build=binary -us -uc

# Install it to make sure it works
RUN dpkg -i /pkg/*.deb
RUN runc --version
RUN containerd --version
RUN crictl-latest --version
RUN podman --version
RUN conmon --version
RUN dpkg -L k8s-worker-containerd

# Now prepare the real output: a tarball of /out, and the .deb for this arch.
WORKDIR /artifacts
RUN cp -v /pkg/*.deb .
WORKDIR /out
RUN tar czvf /artifacts/k8s-worker-containerd_${PACKAGE_VERSION}_${OS_ARCH}.tar.gz *

# Final stage is just alpine so we can start a fake container just to get at its contents using docker in GHA
FROM alpine:3.14.2
COPY --from=build /artifacts/* /out/

