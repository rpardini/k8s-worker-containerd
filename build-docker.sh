#!/usr/bin/env bash

rm -rf ./out
docker buildx build --progress=plain --platform=linux/amd64 --build-arg BASE_IMAGE=ubuntu:jammy -t containerd:amd64 .
docker cp $(docker create --rm containerd:amd64):/out ./
ls -lah ./out/
