# Fix Volume Mount - Recreate Container

## Issue

After changing the volume mount in `docker-compose.yml`, the files are still not visible because:
- **`docker compose restart`** doesn't apply volume changes
- **Volume mounts are applied only when containers are created**, not restarted

## Solution: Recreate the Vector Container

You need to **recreate** (not just restart) the Vector container to apply the new volume mount:

```bash
# Option 1: Recreate just Vector (recommended)
docker compose up -d --force-recreate vector

# Option 2: Stop, remove, and recreate
docker compose stop vector
docker compose rm -f vector
docker compose up -d vector

# Option 3: Recreate all containers (if needed)
docker compose up -d --force-recreate
```

## Verification Steps

**1. First, verify files exist on HOST:**
```bash
# Run this on DEV1 to check if files exist on host
ls -la /data/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
ls -la /data/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out
ls -la /data/logs/app1/var/log/haproxy.log
ls -la /data/logs/app2/var/log/haproxy.log
ls -la /data/logs/app1/var/log/mail.log
ls -la /data/logs/app2/var/log/mail.log
```

**2. After recreating Vector, verify files are visible in container:**
```bash
docker exec moad-vector ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
docker exec moad-vector ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out
docker exec moad-vector ls -la /data/moad/logs/app1/var/log/haproxy.log
docker exec moad-vector ls -la /data/moad/logs/app2/var/log/haproxy.log
docker exec moad-vector ls -la /data/moad/logs/app1/var/log/mail.log
docker exec moad-vector ls -la /data/moad/logs/app2/var/log/mail.log
```

**3. Check Vector logs to see if it's reading files:**
```bash
docker logs moad-vector --tail 50 | grep -i "file\|read\|ingest"
```

**4. Verify Vector is sending to Loki:**
```bash
docker logs moad-vector --tail 50 | grep -i "loki\|sending"
```

## Troubleshooting

### If files still don't appear after recreate:

1. **Check docker-compose.yml mount is correct:**
   ```bash
   grep -A 3 "volumes:" docker-compose.yml | grep "/data/logs"
   ```
   Should show: `- /data/logs:/data/moad/logs:ro`

2. **Verify files exist on host:**
   ```bash
   find /data/logs -name "catalina.out" -o -name "haproxy.log" -o -name "mail.log" 2>/dev/null
   ```

3. **Check container mount:**
   ```bash
   docker inspect moad-vector | grep -A 10 "Mounts"
   ```
   Look for the `/data/logs:/data/moad/logs` mount

4. **Check permissions:**
   ```bash
   ls -la /data/logs/app1/usr/share/apache-tomcat-8.5.94/logs/
   ```
   Files should be readable

