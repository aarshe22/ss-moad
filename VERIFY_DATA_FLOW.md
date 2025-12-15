# Verify Data Flow: Loki, Prometheus, and Grafana

## Quick Verification Checklist

### ✅ 1. Verify Datasources in Grafana

1. **Open Grafana**: `http://dev1.schoolsoft.net:3000`
2. **Navigate**: Configuration (gear icon) → **Data Sources**
3. **Verify both datasources exist**:
   - **Loki** (should be default, green checkmark)
   - **Prometheus** (should have green checkmark)

**If datasources show errors:**
- Check container names match service names in Docker network
- Verify containers are running: `docker ps | grep -E "loki|prometheus|grafana"`
- Check network connectivity: `docker network inspect ss-moad_moad-network`

### ✅ 2. Test Loki Connection (Explore Logs)

1. **In Grafana**: Click **Explore** (compass icon) in left sidebar
2. **Select datasource**: Choose **Loki** from dropdown
3. **Run a test query**:
   ```
   {app="CM"}
   ```
   or
   ```
   {app=~"CM|PFM"}
   ```
4. **Expected**: Should see log lines (if Vector is processing logs)

**If no logs appear:**
- Check Vector is running: `docker logs moad-vector --tail 50`
- Check Vector is sending to Loki: `docker logs moad-vector | grep -i loki`
- Check Loki is receiving: `docker logs moad-loki --tail 50`
- Verify log files exist: `ls -la /data/moad/logs/app*/usr/share/apache-tomcat*/logs/catalina.out`

### ✅ 3. Test Prometheus Connection

1. **In Grafana Explore**: Select **Prometheus** datasource
2. **Run a test query**:
   ```
   up
   ```
   or
   ```
   mysql_global_status_connections
   ```
3. **Expected**: Should see metric data points

**If no metrics appear:**
- Check Prometheus targets: `http://dev1.schoolsoft.net:9090/targets` (if port exposed)
- Or: `docker exec moad-prometheus wget -qO- http://localhost:9090/targets`
- Check MySQL Exporter is running: `docker logs moad-mysqld-exporter --tail 50`
- Verify Prometheus config: `docker exec moad-prometheus cat /etc/prometheus/prometheus.yml`

### ✅ 4. Verify Vector → Loki Pipeline

**Check Vector is processing logs:**
```bash
# Check Vector logs for errors
docker logs moad-vector --tail 100 | grep -i error

# Check Vector is reading log files
docker logs moad-vector | grep -i "file.*read\|ingesting"

# Check Vector is sending to Loki
docker logs moad-vector | grep -i "loki\|sending"
```

**Check Loki is receiving logs:**
```bash
# Check Loki logs for incoming requests
docker logs moad-loki --tail 100 | grep -i "push\|ingest"

# Check Loki metrics (if available)
docker exec moad-loki wget -qO- http://localhost:3100/metrics | grep loki_ingester
```

**Verify log files are accessible:**
```bash
# Check log files exist and are readable
ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out

# Check if Vector can read them (from inside container)
docker exec moad-vector ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
```

### ✅ 5. Test Dashboard Queries

**Open a dashboard** (e.g., "MOAD - Global Platform Overview"):

1. **Check for "No data" panels**:
   - If panels show "No data", queries may need adjustment
   - Check time range (top right) - try "Last 24 hours" or "Last 7 days"

2. **Test individual panel queries**:
   - Click on a panel → **Edit**
   - Check the query in the query editor
   - Click **Run query** to test

3. **Common issues**:
   - **No data**: Logs/metrics may not have the expected labels
   - **Query errors**: Check datasource UID matches (`Loki`, `Prometheus`)
   - **Time range**: Ensure data exists for selected time range

### ✅ 6. Verify Data Labels

**In Grafana Explore with Loki selected**, run:
```
label_values(app)
```
Should return: `CM`, `PFM`

```
label_values(host)
```
Should return: `app1`, `app2`

```
label_values(event_type)
```
Should return various event types if Vector is classifying events

**If labels are missing:**
- Check Vector transforms are adding labels correctly
- Verify Vector config: `docker exec moad-vector cat /etc/vector/vector.yml | grep -A 10 "labels:"`

## Troubleshooting Commands

### Check All Container Health
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Check Container Logs for Errors
```bash
# Vector
docker logs moad-vector --tail 50 | grep -i error

# Loki
docker logs moad-loki --tail 50 | grep -i error

# Prometheus
docker logs moad-prometheus --tail 50 | grep -i error

# MySQL Exporter
docker logs moad-mysqld-exporter --tail 50 | grep -i error

# Grafana
docker logs moad-grafana --tail 50 | grep -i error
```

### Test Network Connectivity
```bash
# From Grafana container to Loki
docker exec moad-grafana wget -qO- http://loki:3100/ready

# From Grafana container to Prometheus
docker exec moad-grafana wget -qO- http://prometheus:9090/-/healthy

# From Vector container to Loki
docker exec moad-vector wget -qO- http://loki:3100/ready
```

### Check Vector Structured Logs
```bash
# Count records in structured logs
find data/vector/structured -name "*.jsonl.gz" -exec zcat {} \; | wc -l

# View latest structured log entries
find data/vector/structured -name "*.jsonl.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2- | xargs zcat | tail -20
```

## Expected Data Flow

```
Log Files (NFS)
    ↓
Vector (reads, parses, enriches)
    ↓
    ├─→ Loki (log aggregation) ──→ Grafana (dashboards)
    └─→ Structured Files (JSONL) (archival)
    
MySQL Server
    ↓
MySQL Exporter (scrapes metrics)
    ↓
Prometheus (collects metrics) ──→ Grafana (dashboards)
```

## Next Steps After Verification

Once data is flowing:

1. **Customize Dashboards**: Adjust queries, thresholds, and visualizations
2. **Set Up Alerts**: Configure alert rules in Grafana
3. **Optimize Queries**: Fine-tune LogQL and PromQL queries for performance
4. **Add More Dashboards**: Create custom dashboards for specific use cases
5. **Document Queries**: Save useful queries for future reference

## Common Issues and Solutions

### Issue: "No data" in all dashboards
**Solution**: 
- Check time range (may need to go back further)
- Verify Vector is processing logs (check Vector logs)
- Verify log files exist and have recent data

### Issue: Datasource connection errors
**Solution**:
- Verify service names in docker-compose.yml match datasource URLs
- Check Docker network: `docker network inspect ss-moad_moad-network`
- Restart containers: `docker compose restart grafana loki prometheus`

### Issue: Labels not appearing in Grafana
**Solution**:
- Check Vector is adding labels correctly (see `sinks.loki_all.labels` in vector.yml)
- Verify Vector transforms are setting `app`, `host`, `event_type` fields
- Check Loki is receiving labeled logs: `docker logs moad-loki | grep labels`

### Issue: Prometheus shows "down" targets
**Solution**:
- Check MySQL Exporter is running: `docker ps | grep mysqld-exporter`
- Verify MySQL connection: `docker logs moad-mysqld-exporter`
- Check Prometheus scrape config: `docker exec moad-prometheus cat /etc/prometheus/prometheus.yml`

