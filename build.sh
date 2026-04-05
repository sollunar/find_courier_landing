#!/bin/bash
set -euo pipefail

IMAGE_NAME="shamad/find-courier-site:latest"
PLATFORM="${PLATFORM:-linux/amd64}"

echo "Building and pushing $IMAGE_NAME for $PLATFORM"
docker buildx build --platform "$PLATFORM" -t "$IMAGE_NAME" --push .
