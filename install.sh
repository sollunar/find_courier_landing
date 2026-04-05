#!/bin/bash
set -e

FINDCOURIER_IMAGE="shamad/find-courier-site:latest"

# Create the directory for SSL certs if it doesn't exist
if [ ! -d /var/lib/findcourier ]; then
        echo "Creating /var/lib/findcourier directory..."
        mkdir -p /var/lib/findcourier
fi

echo "Please make sure your SSL certificate and key are in /var/lib/findcourier:"
echo "  findcourier.crt"
echo "  findcourier.key"

# Pull the published image first so deploys don't build locally
echo "Pulling image: $FINDCOURIER_IMAGE"
docker pull "$FINDCOURIER_IMAGE"

echo "Starting the container..."
FINDCOURIER_IMAGE="$FINDCOURIER_IMAGE" docker compose up -d

# Show running containers
docker ps
