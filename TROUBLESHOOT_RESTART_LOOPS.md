# Troubleshooting Restart Loops

## Check Container Logs

Run these commands on DEV1 to diagnose the restart loops:

```bash
# Check Vector logs
docker logs moad-vector --tail 50

# Check MySQL Exporter logs
docker logs moad-mysqld-exporter --tail 50

# Check all container status
docker compose ps

# Check recent logs for all services
docker compose logs --tail 50
```

## Common Issues

### Vector Restarting (Exit Code 78)
- Usually indicates configuration file error
- Check: `docker logs moad-vector`
- Verify: `vector/vector.yml` syntax is correct
- Verify: Vector config file is mounted correctly

### MySQL Exporter Restarting (Exit Code 1)
- Usually indicates connection failure
- Check: `docker logs moad-mysqld-exporter`
- Verify: MySQL host is accessible
- Verify: `MYSQL_HOST` is set in `.env` file (IP address or hostname)
- Verify: `MYSQL_MOAD_RO_PASSWORD` is set in `.env`
- Verify: `moad_ro` user exists and has correct permissions

## Quick Fixes

### If Vector is failing:
```bash
# Check Vector config syntax
docker run --rm -v $(pwd)/vector/vector.yml:/etc/vector/vector.yml:ro timberio/vector:0.38.0-alpine validate --config-dir /etc/vector

# Or check logs for specific error
docker logs moad-vector 2>&1 | grep -i error
```

### If MySQL Exporter is failing:
```bash
# Verify .env file has both MYSQL_HOST and password
cat .env | grep MYSQL_HOST
cat .env | grep MYSQL_MOAD_RO_PASSWORD

# Test MySQL connection (replace ${MYSQL_HOST} with actual value from .env)
docker run --rm --network ss-moad_moad-network mysql:8.0 mysql -h ${MYSQL_HOST} -u moad_ro -p${MYSQL_MOAD_RO_PASSWORD} -e "SELECT 1"

# Check if MySQL host is reachable from container network
docker run --rm --network ss-moad_moad-network alpine ping -c 3 ${MYSQL_HOST}
```

