# MySQL Monitoring in MOAD

## Overview

MOAD includes comprehensive MySQL observability covering both business data analytics and low-level performance monitoring for the `schoolsoft` and `permissionMan` databases.

## MySQL Exporter Configuration

### User: `moad_ro`

The MySQL exporter uses a read-only user `moad_ro` with the following access:

**Grants:**
- `SELECT ON schoolsoft.*`
- `SELECT ON permissionMan.*`
- `SELECT ON performance_schema.*`
- `SELECT ON information_schema.*`

**Explicitly Denied:**
- `mysql.*` (system database)
- `SUPER` privilege
- `PROCESS` privilege
- `RELOAD` privilege
- `EVENT` privilege
- `REPLICATION CLIENT` privilege

### Connection String

Configured in `docker-compose.yml`:
```yaml
DATA_SOURCE_NAME: "moad_ro:${MYSQL_MOAD_RO_PASSWORD}@tcp(${MYSQL_HOST}:3306)/"
```

**Note:** `MYSQL_HOST` must be set in `.env` file (IP address or hostname). Using an IP address is recommended for reliability in Docker networks.

## Performance Metrics

### InnoDB Metrics

- **Buffer Pool Utilization**: Data and free space in buffer pool
- **Buffer Pool Hit Ratio**: Should be >99%. Lower values indicate insufficient buffer pool size
- **Row Lock Waits**: Contention indicators
- **Row Lock Time**: Time spent waiting for locks

### Query Performance

- **Query Latency (p95/p99)**: Percentile query response times
- **Slow Queries**: Rate of queries exceeding `long_query_time`
- **Queries Per Second**: Overall query throughput
- **Table Open Cache Hit Ratio**: Efficiency of table descriptor caching

### Connection Metrics

- **Threads Connected**: Current connection count
- **Threads Running**: Active query threads
- **Max Connections**: Connection limit
- **Aborted Connects/Clients**: Connection errors

### Schema Growth

- **Table Row Counts**: Growth trends for all tables
- **Database Size**: Storage utilization over time

## Application Analytics

### PermissionMan Schema

The `permissionMan` database is a large, highly relational schema supporting:
- District, school, staff, student, parent entities
- Form lifecycle management
- Audit trails
- Policy management
- Notification workflows
- Integration tasks

### Key Tables Monitored

- **Form**: Form definitions
- **FormDistribution**: Form distribution events
- **UserForm**: User-form associations and status
- **UserFormAudit**: Action audit trail
- **UserFormNotificationQueue**: Email notification queue
- **FullIntegrationTask**: Full SIS integration tasks
- **DeltaIntegrationTask**: Incremental integration tasks
- **District, School, User, Student, Parent**: Core entities

### Analytics Focus Areas

1. **Form Lifecycle**
   - Distribution → Completion → Expiration → Archival
   - Status transitions over time
   - Per-school and per-district activity

2. **User Activity**
   - UserFormAudit actions over time
   - Form completion rates
   - User engagement patterns

3. **Integration Performance**
   - Integration task timing
   - Success/failure rates
   - Correlation with SIS availability

4. **Notification Delivery**
   - Queue size trends
   - Correlation with email delivery logs
   - Delivery success rates

5. **Growth Trends**
   - Per-district and per-school growth
   - Table size trends
   - Usage patterns over time

## Dashboards

### MySQL Performance Dashboard

**Location:** `grafana/dashboards/mysql-performance.json`

**Panels:**
- MySQL Up Status
- Threads Connected vs Max Connections
- Threads Running
- InnoDB Buffer Pool Utilization
- Buffer Pool Hit Ratio
- Query Latency (p95/p99)
- InnoDB Row Lock Waits
- Queries Per Second
- Table Open Cache Hit Ratio
- Connection Errors
- Schema and Table Growth

### PermissionMan Analytics Dashboard

**Location:** `grafana/dashboards/permissionman-analytics.json`

**Panels:**
- PermissionMan Database Status
- Form Lifecycle - Distribution Status
- Form Activity by Status
- UserFormAudit Actions Over Time
- Email Notifications Queue
- Integration Task Activity
- Form Events from Logs (PFM Application)
- Database Growth Trends
- Form Activity Rate (from Logs)

**Templating Variables:**
- `district_id`: Filter by district
- `school_id`: Filter by school (dependent on district)

### Correlation Dashboard

**Location:** `grafana/dashboards/correlation-dashboard.json`

**Panels:**
- Authentication Failures vs MySQL Threads
- Application Requests vs MySQL Query Rate
- PowerSchool Integration vs Slow Queries
- Form Activity vs Database Load
- Email Delivery vs Notification Queue
- Conference Activity vs Database Connections
- InnoDB Buffer Pool Hit Ratio vs Query Rate
- Root Cause Analysis - Event Timeline

## Log Integration

### Form Events

Vector extracts form-related events from PFM (and CM) logs:

**Event Type:** `form`

**Extracted Identifiers:**
- `form_id` → `permissionMan.Form.id`
- `user_form_id` → `permissionMan.UserForm.id`
- `user_id` → `permissionMan.User.id`
- `school_id` → `permissionMan.School.id`
- `district_id` → `permissionMan.District.id`
- `student_id` → `permissionMan.Student.id`
- `form_action`: distributed, completed, submitted, expired, archived, etc.
- `form_status`: Current form status

**Join Hints:**
```json
{
  "mysql_joins": [
    "permissionMan.Form.id",
    "permissionMan.UserForm.id",
    "permissionMan.User.id",
    "permissionMan.School.id",
    "permissionMan.District.id"
  ]
}
```

### Integration Task Events

**Event Type:** `integration_task`

**Extracted Identifiers:**
- `integration_task_id` → `permissionMan.FullIntegrationTask.id` or `DeltaIntegrationTask.id`
- `integration_type`: full, delta, incremental
- `school_id`, `district_id`
- `integration_status`: success, failed, error, completed, running, pending

## Security Considerations

### Least Privilege Principle

- Read-only access only
- No write operations
- No system database access
- No administrative privileges

### Credential Management

- MySQL password stored in `.env` file (not committed to git)
- Environment variable: `MYSQL_MOAD_RO_PASSWORD`
- Credentials never exposed in logs or dashboards

### Query Restrictions

Per MOAD non-goals:
- No inline DB queries from Grafana for time-series data
- Use metrics and logs for time-series queries
- MySQL datasource used sparingly for metadata lookups only

## Alerting Recommendations

### Performance Alerts

1. **Connection Saturation**
   - Alert when `threads_connected / max_connections > 0.9`
   - Indicates potential connection exhaustion

2. **Buffer Pool Hit Ratio**
   - Alert when hit ratio < 95%
   - Indicates insufficient buffer pool size

3. **Lock Contention**
   - Alert when `innodb_row_lock_waits > 10/sec`
   - Indicates transaction conflicts

4. **Slow Queries**
   - Alert when slow query rate spikes
   - Indicates query performance degradation

### Application Alerts

1. **Notification Queue**
   - Alert when `UserFormNotificationQueue` size > 1000
   - Indicates email delivery issues

2. **Integration Task Failures**
   - Alert on integration task failure spikes
   - Correlate with SIS availability

## Troubleshooting

### MySQL Exporter Not Connecting

1. Verify MySQL host is accessible from container network
2. Check `moad_ro` user exists and has correct grants
3. Verify password in `.env` file
4. Check exporter logs: `docker logs moad-mysqld-exporter`

### Missing Metrics

1. Verify `performance_schema` is enabled in MySQL
2. Check exporter has access to `performance_schema.*`
3. Verify `information_schema` access
4. Check Prometheus targets: http://localhost:9090/targets

### High Query Latency

1. Check buffer pool hit ratio
2. Review slow query log
3. Correlate with application activity (logs)
4. Check for lock contention
5. Review table growth trends

## Best Practices

1. **Monitor Buffer Pool**: Ensure hit ratio stays >99%
2. **Track Connection Usage**: Keep below 80% of max_connections
3. **Correlate Metrics**: Always correlate DB metrics with application logs
4. **Use Join Hints**: Leverage `mysql_joins` array in logs for correlation
5. **Trend Analysis**: Monitor table growth for capacity planning
6. **Root Cause Analysis**: Use correlation dashboard for multi-layer analysis

## Future Enhancements

1. **Custom Metrics**: Export application-specific metrics (e.g., form completion rates)
2. **Query Digest Analysis**: Track top query patterns
3. **Table-Level Metrics**: Per-table performance metrics
4. **Replication Lag**: If replication is used
5. **Backup Status**: Monitor backup completion and size

