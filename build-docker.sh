#!/usr/bin/env bash
set -e

rm -rf ./out
#docker buildx build --progress=plain --platform=linux/amd64 --pull --build-arg BASE_IMAGE=ubuntu:jammy --build-arg OS_ARCH=amd64 -t containerd:amd64 .
#docker buildx build --progress=plain --platform=linux/amd64 --pull --build-arg BASE_IMAGE=debian:bullseye --build-arg OS_ARCH=amd64 -t containerd:amd64 .
docker buildx build --progress=plain --platform=linux/amd64 --pull --build-arg BASE_IMAGE=debian:trixie --build-arg OS_ARCH=amd64 -t containerd:amd64 .
docker cp $(docker create --rm containerd:amd64):/out ./
ls -lah ./out/
