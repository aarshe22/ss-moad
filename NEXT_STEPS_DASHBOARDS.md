# Next Steps: Getting Amazing Dashboards

## ✅ Current Status

All containers are running! You have:
- **4 Pre-built Dashboards** ready to use
- **3 Datasources** configured (Loki, Prometheus, MySQL needs manual setup)
- **Auto-provisioning** enabled (dashboards refresh every 10 seconds)

## Step 1: Verify Datasources

### In Grafana UI:

1. **Go to Configuration → Data Sources**
   - You should see:
     - ✅ **Loki** (http://loki:3100) - Should be green/working
     - ✅ **Prometheus** (http://prometheus:9090) - Should be green/working
     - ⚠️ **MySQL** - Needs manual configuration (see below)

2. **Test each datasource:**
   - Click on "Loki" → Click "Save & Test" (should show "Data source connected and labels found")
   - Click on "Prometheus" → Click "Save & Test" (should show "Data source is working")

### Configure MySQL Datasource (Optional):

The MySQL datasource is provisioned but needs the host URL updated:

1. Go to **Configuration → Data Sources → MySQL**
2. Update the **Host** field:
   - Current: `mysql-host:3306`
   - Change to: Your actual MySQL host (from `.env` file `MYSQL_HOST` value)
   - Example: `10.0.0.13:3306` or `mysql-server.example.com:3306`
3. Update **Database**: `schoolsoft` (or `permissionMan` if preferred)
4. Update **User**: `grafana_readonly` (or your MySQL Grafana user)
5. Update **Password**: Use `MYSQL_GRAFANA_PASSWORD` from your `.env` file
6. Click **Save & Test**

**Note:** Per MOAD non-goals, MySQL datasource should be used sparingly (metadata lookups only, not time-series queries).

## Step 2: Verify Dashboards Are Loaded

1. **Go to Dashboards → Browse**
2. **Look for folder:** "MOAD / Executive"
3. **You should see 4 dashboards:**
   - **MySQL Performance** - InnoDB, queries, locks, connections
   - **PermissionMan Analytics** - Forms, activity, trends
   - **Correlation Dashboard** - Logs + metrics + DB performance
   - **Authentication Failures** - Security monitoring

4. **Open each dashboard** to verify they load:
   - If panels show "No data", that's normal if logs/metrics haven't accumulated yet
   - Check the time range (top right) - try "Last 1 hour" or "Last 6 hours"

## Step 3: Verify Data Is Flowing

### Check Logs Are Being Ingested:

1. **In Grafana, create a test query:**
   - Go to **Explore** (compass icon)
   - Select **Loki** datasource
   - Try query: `{app="CM"}` or `{app="PFM"}`
   - Click **Run query**
   - You should see log entries if Vector is processing logs

2. **Check Vector structured logs:**
   ```bash
   # Check if structured logs are being created
   ls -la data/vector/structured/
   
   # View recent structured logs
   tail -20 data/vector/structured/*.jsonl 2>/dev/null | head -20
   ```

### Check Metrics Are Being Collected:

1. **In Grafana Explore, select Prometheus:**
   - Try query: `mysql_up`
   - Should return `1` if MySQL exporter is working
   - Try: `vector_events_processed_total` to see Vector metrics

2. **Check Prometheus targets:**
   - Go to: http://dev1.schoolsoft.net:9090/targets
   - All targets should show as "UP" (green)

## Step 4: Customize Dashboards

### Quick Wins:

1. **Adjust Time Ranges:**
   - Each dashboard has a refresh interval (30s default)
   - Adjust time range selector (top right) based on your needs

2. **Add Variables:**
   - Some dashboards have template variables (district_id, school_id)
   - Use these to filter data by school or district

3. **Modify Panels:**
   - Click panel title → **Edit**
   - Adjust queries, thresholds, visualizations
   - Click **Save dashboard** when done

### Create Custom Dashboards:

1. **Click "+" → Create Dashboard**
2. **Add panels** using:
   - **Loki queries** for log analysis
   - **Prometheus queries** for metrics
   - **Mixed datasources** for correlation

3. **Example Queries to Get Started:**

   **Log Queries (Loki):**
   ```
   {app="CM", event_type="authentication", auth_result="failed"}
   {app="PFM", event_type="form", form_action="completed"}
   {level="error"}
   ```

   **Metric Queries (Prometheus):**
   ```
   mysql_global_status_threads_connected
   mysql_innodb_buffer_pool_read_requests
   rate(mysql_global_status_queries[5m])
   ```

## Step 5: Set Up Alerts (Recommended)

### Create Alert Rules:

1. **Go to Alerting → Alert Rules → New Alert Rule**

2. **Example Alert: High Authentication Failures**
   - **Query:** `sum(rate({app=~"CM|PFM", auth_result="failed"}[5m])) > 10`
   - **Condition:** When last value is above 10 failures/minute
   - **Notification:** Email, Slack, or webhook

3. **Example Alert: MySQL Connection Saturation**
   - **Query:** `mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.8`
   - **Condition:** When above 80% connection usage
   - **Notification:** Send alert

4. **Example Alert: Vector Not Processing**
   - **Query:** `vector_events_processed_total` (no increase in 5 minutes)
   - **Condition:** When rate is zero
   - **Notification:** Critical alert

## Step 6: Explore Advanced Features

### Correlation Queries:

Use the **Correlation Dashboard** to see relationships between:
- Authentication failures vs MySQL connection spikes
- Form activity vs database load
- Email delivery vs notification queue

### Join Hints:

Logs include `mysql_joins` arrays showing which MySQL tables can be joined:
- Look for `mysql_join_school_id`, `mysql_join_user_id`, etc. in log fields
- Use these for correlating logs with database records

### Derived Fields:

Loki has derived fields configured to link to Prometheus:
- Click on log entries with `mysql_join_*` fields
- These can link to related metrics

## Troubleshooting

### Dashboards Show "No Data":

1. **Check time range** - Try "Last 6 hours" or "Last 24 hours"
2. **Verify datasources** - Test each datasource connection
3. **Check data is flowing:**
   ```bash
   # Check Vector logs
   docker logs moad-vector | tail -20
   
   # Check Loki has data
   curl -G "http://localhost:3100/loki/api/v1/query" --data-urlencode 'query={app="CM"}' --data-urlencode 'limit=5'
   
   # Check Prometheus has metrics
   curl http://localhost:9090/api/v1/query?query=mysql_up
   ```

### MySQL Metrics Not Appearing:

1. **Verify MySQL Exporter is connected:**
   ```bash
   docker logs moad-mysqld-exporter | tail -20
   ```

2. **Check Prometheus is scraping:**
   - Go to http://dev1.schoolsoft.net:9090/targets
   - Look for `mysqld-exporter` target
   - Should show "UP"

3. **Verify MySQL user permissions:**
   - Ensure `moad_ro` user has SELECT on `performance_schema.*`

### Logs Not Appearing:

1. **Check Vector is processing:**
   ```bash
   docker logs moad-vector | grep -i error
   ```

2. **Verify log paths exist:**
   ```bash
   ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
   ```

3. **Check NFS mounts:**
   - Verify `/data/moad/logs` is mounted and readable

## Quick Reference

### Access URLs:
- **Grafana:** http://dev1.schoolsoft.net:3000
- **Prometheus:** http://dev1.schoolsoft.net:9090
- **Loki:** http://dev1.schoolsoft.net:3100

### Useful Commands:
```bash
# View Grafana password
./show-grafana-url.sh

# Check all container status
docker compose ps

# View recent errors
./moad-manager.sh
# Select "10. Docker: View Recent Errors"

# Check service health
./moad-manager.sh
# Select "14. Services: Check Service Health"
```

## Next Level: Custom Dashboards

Once you're comfortable with the pre-built dashboards, consider creating:

1. **Application-Specific Dashboards:**
   - CM (Conference Manager) activity
   - PFM (Permission Form Manager) activity
   - Per-school performance

2. **Business Intelligence Dashboards:**
   - User engagement metrics
   - Form completion rates
   - Integration task success rates

3. **Security Dashboards:**
   - Failed login attempts by school
   - Suspicious activity patterns
   - Access pattern anomalies

4. **Operational Dashboards:**
   - System health overview
   - Resource utilization
   - Error rate trends

## Documentation

For detailed information, see:
- `docs/MYSQL_MONITORING.md` - MySQL metrics and dashboards
- `docs/JOIN_COMPATIBILITY.md` - How to join logs with database
- `docs/SCHEMA_MAPPING.md` - Log fields to MySQL columns mapping

