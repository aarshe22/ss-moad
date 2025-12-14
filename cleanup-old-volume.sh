#!/bin/bash
# Cleanup script to remove old vector-structured volume

echo "Stopping all containers..."
docker compose down -v --remove-orphans

echo "Removing old vector-structured volume if it exists..."
docker volume rm ss-moad_vector-structured 2>/dev/null || echo "Volume already removed or doesn't exist"

echo "Removing any volumes with 'vector' in the name..."
docker volume ls | grep vector | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

echo "Pruning orphaned volumes..."
docker volume prune -f

echo "Cleaning up any stopped containers..."
docker container prune -f

echo "Done! Now run: docker compose up -d"

