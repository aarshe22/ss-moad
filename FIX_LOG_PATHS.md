# Fix Log Path Configuration

## Issue Identified

The diagnostic shows:
- **NFS mounts are at**: `/data/logs/app1` and `/data/logs/app2` (on host)
- **Vector config expects**: `/data/moad/logs/app1/...` and `/data/moad/logs/app2/...` (in container)
- **Current docker-compose mount**: `/data/moad/logs:/data/moad/logs` (mounts wrong path)

## Solution

Updated `docker-compose.yml` to mount the actual NFS mount location to where Vector expects it:

```yaml
volumes:
  - /data/logs:/data/moad/logs:ro  # NFS mounts are at /data/logs/app1 and /data/logs/app2
```

This way:
- Host has NFS at `/data/logs/app1` and `/data/logs/app2`
- Container sees them at `/data/moad/logs/app1` and `/data/moad/logs/app2`
- Vector config doesn't need to change

## Next Steps

1. **Restart Vector container** to pick up the new mount:
   ```bash
   docker compose restart vector
   ```

2. **Verify Vector can see the log files**:
   ```bash
   docker exec moad-vector ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
   docker exec moad-vector ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out
   ```

3. **Check Vector logs** to see if it's now reading files:
   ```bash
   docker logs moad-vector --tail 50 | grep -i "file\|read\|ingest"
   ```

4. **Verify logs are flowing to Loki**:
   ```bash
   # In Grafana Explore, try query:
   {app="CM"}
   ```

## Alternative: If NFS Mounts Are Different

If your actual NFS mounts are at a different location, you can:

1. **Find actual mount location**:
   ```bash
   mount | grep nfs
   find /data -type d -name "app1" -o -name "app2" 2>/dev/null
   ```

2. **Update docker-compose.yml** with the correct host path:
   ```yaml
   volumes:
     - /actual/path/to/logs:/data/moad/logs:ro
   ```

3. **Restart Vector**:
   ```bash
   docker compose restart vector
   ```

