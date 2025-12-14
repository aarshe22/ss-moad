# MOAD Deployment Checklist

## Pre-Deployment Verification

### ✅ File Structure
- [x] `docker-compose.yml` - Service definitions
- [x] `vector/vector.yml` - Log processing pipeline
- [x] `loki/loki-config.yml` - Log aggregation config
- [x] `prometheus/prometheus.yml` - Metrics collection config
- [x] `grafana/provisioning/datasources/datasources.yml` - Grafana datasources
- [x] `grafana/provisioning/dashboards/dashboards.yml` - Dashboard provisioning
- [x] `grafana/dashboards/authentication-failures.json` - Sample dashboard
- [x] `README.md` - Project documentation
- [x] `docs/` - All documentation files

### ⚠️ Required Environment Setup

#### 1. Environment Variables
Create `.env` file with:
```bash
GRAFANA_ADMIN_PASSWORD=<secure_password>
MYSQL_MOAD_RO_PASSWORD=<moad_ro_password>
MYSQL_GRAFANA_PASSWORD=<grafana_readonly_password>
```

**Note:** `MYSQL_MOAD_RO_PASSWORD` is for the `moad_ro` MySQL user which has:
- `SELECT ON schoolsoft.*`
- `SELECT ON permissionMan.*`
- `SELECT ON performance_schema.*`
- `SELECT ON information_schema.*`
- No write access, no system database access

#### 2. Log Directory Access
Ensure `/data/moad/logs` is accessible:
- NFS mount configured
- Read permissions for Docker containers
- Log files exist at expected paths:
  - `/data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out`
  - `/data/moad/logs/app1/var/log/haproxy.log`
  - `/data/moad/logs/app1/var/log/mail.log`
  - `/data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out`
  - `/data/moad/logs/app2/var/log/haproxy.log`
  - `/data/moad/logs/app2/var/log/mail.log`

#### 3. MySQL Database Access
- MySQL host accessible from `mysqld-exporter` container
- Add `mysql-host` alias to Docker host `/etc/hosts` file (see deployment steps below)
- MySQL user `moad_ro` exists with read-only permissions:
  - `SELECT ON schoolsoft.*`
  - `SELECT ON permissionMan.*`
  - `SELECT ON performance_schema.*`
  - `SELECT ON information_schema.*`
- Databases `schoolsoft` and `permissionMan` exist
- `performance_schema` is enabled in MySQL

#### 4. Network Configuration
- Ports available: 3000, 3100, 9090, 9104
- Docker network can be created
- Containers can communicate on `moad-network`

## Deployment Steps

### 1. Clone/Pull Repository
```bash
git clone <repository-url>
cd ss-moad
# OR if updating:
git pull origin main
```

### 2. Create Environment File
```bash
cp .env.example .env
# Edit .env with actual values
```

### 3. Configure MySQL Host Alias
Add `mysql-host` as an alias in your Docker host's `/etc/hosts` file:

```bash
# Edit /etc/hosts (requires sudo)
sudo nano /etc/hosts

# Add a line like this (replace with your actual MySQL hostname or IP):
# 192.168.1.100  mysql-host
# OR if using a hostname:
# mysql-server.example.com  mysql-host
```

**Note:** The `docker-compose.yml` uses `mysql-host` as the hostname. By adding it to `/etc/hosts`, Docker containers will resolve it to your actual MySQL server. This avoids needing to edit the compose file.

### 4. Verify Log Paths
Check that log files exist:
```bash
ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out
```

### 5. Start Services
```bash
docker compose up -d
```

### 6. Verify Services
```bash
docker compose ps
# All services should show "Up"
```

### 7. Check Logs
```bash
# Vector logs
docker logs moad-vector

# Loki logs
docker logs moad-loki

# Prometheus logs
docker logs moad-prometheus

# Grafana logs
docker logs moad-grafana
```

### 8. Access Services
- Grafana: http://dev1.schoolsoft.net:3000 (admin / password from .env)
- Prometheus: http://dev1.schoolsoft.net:9090
- Loki: http://dev1.schoolsoft.net:3100

## Post-Deployment Validation

### 1. Vector Processing
```bash
# Check Vector is processing logs
docker logs moad-vector | grep -i "error"

# Check structured logs are being created
ls -la vector/structured/
```

### 2. Loki Ingestion
```bash
# Query Loki for test events
curl -G "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={app="CM"}' \
  --data-urlencode 'limit=10'
```

### 3. Prometheus Metrics
```bash
# Check MySQL exporter metrics
curl http://localhost:9104/metrics | grep mysql_up
```

### 4. Grafana Dashboards
- Login to Grafana
- Verify datasources are configured (Loki, Prometheus)
- Check that sample dashboard loads
- Verify queries return data

### 5. Join Compatibility
```bash
# Check structured logs for join hints
cat vector/structured/*.jsonl | jq 'select(.mysql_joins != null)' | head -5
```

## Known Issues & Notes

### Vector Configuration
- HAProxy logs use `parse_apache_log` - may need adjustment based on actual HAProxy log format
- Timestamp parsing uses `parse_timestamp!` - will use `now()` as fallback if parsing fails
- `get_env_var("HOSTNAME")` - defaults to "app1" or "app2" if not set

### Grafana Datasources
- MySQL datasource UID needs to be set after first Grafana startup
- Derived fields configuration may need adjustment based on actual log structure

### MySQL Exporter
- Requires MySQL host to be accessible from container network
- Add `mysql-host` alias to Docker host `/etc/hosts` file (see deployment steps)

## Troubleshooting

### Vector Not Processing Logs
1. Check log file paths exist
2. Verify file permissions
3. Check Vector logs for errors
4. Verify multiline patterns match log format

### Loki Not Receiving Logs
1. Check Vector → Loki connection
2. Verify Loki is running: `docker ps | grep loki`
3. Check Loki logs for errors
4. Verify network connectivity

### Prometheus Not Scraping
1. Check target endpoints are accessible
2. Verify scrape configs in prometheus.yml
3. Check Prometheus targets page: http://localhost:9090/targets

### Grafana Not Loading Dashboards
1. Check datasource connections
2. Verify dashboard JSON is valid
3. Check Grafana logs for errors
4. Verify provisioning paths are correct

## Next Steps After Deployment

1. **Create Additional Dashboards**
   - PowerSchool integration dashboard
   - Email delivery dashboard
   - MySQL performance dashboard
   - Per-school dashboards

2. **Set Up Alerts**
   - Authentication failure spikes
   - MySQL connection saturation
   - Log processing errors

3. **Validate Join Compatibility**
   - Run validation script (see docs/VALIDATION_GUIDE.md)
   - Verify identifiers match MySQL schema
   - Test join queries in Grafana

4. **Performance Tuning**
   - Adjust Vector batch sizes
   - Tune Loki retention
   - Optimize Prometheus scrape intervals

