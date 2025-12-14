# Fix Docker Volume Issue on Server

## Problem
Docker is trying to use the old cached volume `ss-moad_vector-structured` which conflicts with the read-only `/data/moad/logs` mount.

## Solution - Run on DEV1 Server

```bash
# 1. Navigate to project directory
cd /data/docker/ss-moad

# 2. Stop all containers
docker compose down -v --remove-orphans

# 3. Remove the old volume specifically
docker volume rm ss-moad_vector-structured

# 4. Remove any other vector-related volumes
docker volume ls | grep vector | awk '{print $2}' | xargs docker volume rm 2>/dev/null || true

# 5. Verify the volume is gone
docker volume ls | grep vector
# Should return nothing

# 6. Verify docker-compose.yml is correct (should show ./data/vector/structured)
grep "vector/structured" docker-compose.yml
# Should show: - ./data/vector/structured:/var/lib/vector/structured

# 7. Make sure data directory exists
mkdir -p data/vector/structured

# 8. Start fresh
docker compose up -d

# 9. Verify it worked
docker compose ps
# All services should be "Up"
```

## If Still Failing

If the error persists, try a more aggressive cleanup:

```bash
# Stop everything
docker compose down -v --remove-orphans

# Remove ALL volumes with "moad" in the name
docker volume ls | grep moad | awk '{print $2}' | xargs docker volume rm 2>/dev/null || true

# Prune all unused volumes
docker volume prune -f

# Remove any stopped containers
docker container prune -f

# Verify docker-compose.yml doesn't reference vector-structured volume
grep -i "vector-structured" docker-compose.yml
# Should return nothing

# Start fresh
docker compose up -d
```

## Verify Configuration

After cleanup, verify your docker-compose.yml has:
- `./data/vector/structured:/var/lib/vector/structured` (bind mount, not volume)
- NO `vector-structured:` in the volumes section

