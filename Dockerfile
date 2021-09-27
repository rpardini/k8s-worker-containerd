FROM ubuntu:hirsute as build

ARG CNI_PLUGINS_VERSION="v0.9.1"
ARG RUNC_VERSION="v1.0.2"
ARG CONTAINERD_VERSION="v1.5.5"
ARG CRI_TOOLS_VERSION="v1.22.0"
ARG PACKAGE_VERSION="20210928"
ARG OS_ARCH="amd64"
# or arm64

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -y update
RUN apt-get -y install golang-go git wget build-essential devscripts debhelper libseccomp-dev

# See https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/79a3f79b27bd28f82f071bb877a266c2e62ee506/docs/09-bootstrapping-kubernetes-workers.md#download-and-install-worker-binaries

# Download pre built cni plugins from github releases, they've arm64 and all.
# @TODO maybe the kubelet packages from google .debs actually carry this already?
WORKDIR /src/cni_plugins
SHELL ["/usr/bin/bash", "-e", "-c"]
RUN wget --progress=dot:giga -O "/tmp/cni-plugins-linux.tgz" "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${OS_ARCH}-${CNI_PLUGINS_VERSION}.tgz"
RUN tar -xzf /tmp/cni-plugins-linux.tgz


# Build runc from source
WORKDIR /src
RUN git clone --single-branch --branch=${RUNC_VERSION} https://github.com/opencontainers/runc /src/runc
WORKDIR /src/runc
RUN make

# Build containerd from source
WORKDIR /src
RUN git clone --depth=1 --single-branch --branch=${CONTAINERD_VERSION} https://github.com/containerd/containerd /src/containerd
WORKDIR /src/containerd
RUN BUILDTAGS=no_btrfs make

# Build crictl from source cri-tools

# Build containerd from source
WORKDIR /src
RUN git clone --depth=1 --single-branch --branch=${CRI_TOOLS_VERSION} https://github.com/kubernetes-sigs/cri-tools /src/cri-tools
WORKDIR /src/cri-tools
RUN make

# Prepare the results in /out
WORKDIR /out/usr/bin
RUN cp -v /src/runc/runc .
RUN cp -v /src/cri-tools/build/bin/* .
RUN cp -v /src/containerd/bin/* .
WORKDIR /out/opt/cni/bin
RUN cp -v /src/cni_plugins/* . # cni plugins


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
RUN crictl --version
RUN dpkg -L k8s-worker-containerd

# Now prepare the real output: a tarball of /out, and the .deb for this arch.
WORKDIR /artifacts
RUN cp -v /pkg/*.deb .
WORKDIR /out
RUN tar czvf /artifacts/k8s-worker-containerd_${PACKAGE_VERSION}_${OS_ARCH}.tar.gz *

# Final stage is just alpine so we can start a fake container just to get at its contents using docker in GHA
FROM alpine:3.14.2
COPY --from=build /artifacts/* /out/

