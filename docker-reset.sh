#!/bin/bash
# docker-reset.sh - Complete Docker cleanup script for MOAD development
# WARNING: This will remove ALL Docker containers, volumes, networks, and images
# Use with caution - this is a nuclear option for development reset

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Docker Complete Reset Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${RED}WARNING: This will remove:${NC}"
echo "  - All containers (running and stopped)"
echo "  - All volumes"
echo "  - All networks (except default)"
echo "  - All unused images"
echo "  - All build cache"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${YELLOW}Stopping MOAD stack...${NC}"
docker compose down -v --remove-orphans 2>/dev/null || true

echo -e "${YELLOW}Stopping all running containers...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true

echo -e "${YELLOW}Removing all containers...${NC}"
docker rm $(docker ps -aq) 2>/dev/null || true

echo -e "${YELLOW}Removing all volumes...${NC}"
docker volume rm $(docker volume ls -q) 2>/dev/null || true

echo -e "${YELLOW}Removing all custom networks...${NC}"
docker network prune -f

echo -e "${YELLOW}Removing all unused images...${NC}"
docker image prune -a -f

echo -e "${YELLOW}Removing build cache...${NC}"
docker builder prune -a -f

echo -e "${YELLOW}Final system prune...${NC}"
docker system prune -a --volumes -f

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Docker reset complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Verification:"
echo "  Containers: $(docker ps -aq | wc -l | tr -d ' ')"
echo "  Volumes: $(docker volume ls -q | wc -l | tr -d ' ')"
echo "  Networks: $(docker network ls -q | wc -l | tr -d ' ')"
echo "  Images: $(docker images -q | wc -l | tr -d ' ')"
echo ""
echo -e "${GREEN}All Docker resources have been cleaned.${NC}"
echo "You can now run 'docker compose up -d' to start fresh."

