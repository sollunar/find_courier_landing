#!/bin/bash
set -e

# Create the directory for SSL certs if it doesn't exist
if [ ! -d /var/lib/findcourier ]; then
	    echo "Creating /var/lib/findcourier directory..."
	        mkdir -p /var/lib/findcourier
fi

echo "Please make sure your SSL certificate and key are in /var/lib/findcourier:"
echo "  findcourier.crt"
echo "  findcourier.key"

# Launch Docker Compose with build
echo "Building and starting the container..."
docker-compose up -d --build

# Show running containers
docker ps
