# Docker Cleanup Commands

## Quick Cleanup (MOAD-specific)

Stop and remove MOAD containers, volumes, and networks:

```bash
# Stop and remove containers, networks (keeps volumes)
docker-compose down

# Stop and remove containers, networks, AND volumes
docker-compose down -v

# Stop, remove, and also remove orphaned containers
docker-compose down -v --remove-orphans
```

## Complete Docker Cleanup

### Option 1: Nuclear Option (Removes Everything)

```bash
# Stop all running containers
docker stop $(docker ps -aq)

# Remove all containers
docker rm $(docker ps -aq)

# Remove all volumes
docker volume rm $(docker volume ls -q)

# Remove all networks (except default ones)
docker network prune -f

# Remove all unused images, containers, networks, and volumes
docker system prune -a --volumes -f
```

### Option 2: Safer Step-by-Step

```bash
# 1. Stop and remove MOAD stack
docker-compose down -v

# 2. Remove all stopped containers
docker container prune -f

# 3. Remove all unused volumes
docker volume prune -f

# 4. Remove all unused networks
docker network prune -f

# 5. Remove all unused images (optional - be careful!)
docker image prune -a -f
```

### Option 3: Complete System Prune (Recommended)

```bash
# Remove all unused containers, networks, images, and volumes
# This is the safest "nuclear" option
docker system prune -a --volumes -f
```

## For Fresh MOAD Start

After cleanup, start fresh:

```bash
# Clean up MOAD specifically
docker-compose down -v --remove-orphans

# Optional: Clean up everything Docker-related
docker system prune -a --volumes -f

# Start fresh
docker-compose up -d
```

## What Each Command Does

- `docker-compose down`: Stops and removes containers and networks
- `docker-compose down -v`: Also removes volumes
- `docker-compose down -v --remove-orphans`: Also removes containers not in compose file
- `docker system prune -a --volumes`: Removes ALL unused Docker resources
- `docker volume prune`: Removes unused volumes
- `docker network prune`: Removes unused networks
- `docker container prune`: Removes stopped containers
- `docker image prune -a`: Removes unused images

## Warning

⚠️ **Be careful with `-a` flags** - they remove ALL unused resources, not just MOAD-related ones!

For MOAD-only cleanup, use:
```bash
docker-compose down -v --remove-orphans
```

