#!/usr/bin/env bash

rm -rf ./out
docker buildx build --progress=plain --platform=linux/amd64 -t containerd:amd64 .
docker cp $(docker create --rm containerd:amd64):/out ./
ls -lah ./out/
