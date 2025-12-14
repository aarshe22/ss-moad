# MOAD Quick Start Guide

## Prerequisites

1. Docker and Docker Compose installed
2. Access to `/data/moad/logs` (NFS mount with log files)
3. MySQL database accessible for metrics
4. Ports 3000, 3100, 9090, 9104 available

## 1. Clone Repository

```bash
git clone <repository-url>
cd ss-moad
```

## 2. Configure Environment

```bash
# Create .env file
cat > .env << EOF
GRAFANA_ADMIN_PASSWORD=your_secure_password_here
MYSQL_MOAD_RO_PASSWORD=your_moad_ro_password
MYSQL_GRAFANA_PASSWORD=your_grafana_readonly_password
EOF
```

**Note:** `MYSQL_MOAD_RO_PASSWORD` is for the `moad_ro` MySQL user (read-only access to schoolsoft and permissionMan databases).

## 3. Configure MySQL Host Alias

Add `mysql-host` as an alias in your Docker host's `/etc/hosts` file:

```bash
# Edit /etc/hosts (requires sudo)
sudo nano /etc/hosts

# Add a line like this (replace with your actual MySQL hostname or IP):
# 192.168.1.100  mysql-host
# OR
# mysql-server.example.com  mysql-host
```

**Note:** The `docker-compose.yml` uses `mysql-host` as the hostname. By adding it to `/etc/hosts`, Docker containers will resolve it to your actual MySQL server without needing to edit the compose file.

## 4. Verify Log Paths

Ensure log files exist:
```bash
ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out
```

## 5. Start Services

```bash
docker compose up -d
```

## 6. Verify Services

```bash
docker compose ps
# Should show all services as "Up"
```

## 7. Access Services

- **Grafana**: http://dev1.schoolsoft.net:3000
  - Username: `admin`
  - Password: (from `.env` file)
- **Prometheus**: http://dev1.schoolsoft.net:9090
- **Loki**: http://dev1.schoolsoft.net:3100

## 8. Verify Log Processing

```bash
# Check Vector is processing logs
docker logs moad-vector | tail -20

# Check structured logs are being created
ls -la vector/structured/

# Query Loki for events
curl -G "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={app="CM"}' \
  --data-urlencode 'limit=5'
```

## 9. Check Join Compatibility

```bash
# View structured logs with join hints
cat vector/structured/*.jsonl 2>/dev/null | jq 'select(.mysql_joins != null) | {event_type, mysql_joins, mysql_join_school_id}' | head -10
```

## Troubleshooting

### Services Not Starting
```bash
# Check logs
docker compose logs

# Restart services
docker compose restart
```

### Vector Not Processing Logs
1. Verify log file paths exist and are readable
2. Check Vector logs: `docker logs moad-vector`
3. Verify file permissions on `/data/moad/logs`

### No Data in Grafana
1. Verify Loki is receiving logs: `docker logs moad-loki`
2. Check datasources are configured in Grafana UI
3. Verify queries return data in Loki: http://localhost:3100/ready

### MySQL Metrics Not Appearing
1. Verify MySQL exporter can connect: `docker logs moad-mysqld-exporter`
2. Check Prometheus targets: http://localhost:9090/targets
3. Verify MySQL host is accessible from container network

## Next Steps

1. Review dashboards in Grafana
2. Create additional dashboards for your use cases
3. Set up alerts for critical events
4. Validate join compatibility (see `docs/VALIDATION_GUIDE.md`)

For detailed information, see:
- `README.md` - Project overview
- `DEPLOYMENT_CHECKLIST.md` - Comprehensive deployment guide
- `docs/` - Technical documentation

