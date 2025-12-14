# MySQL Monitoring Extension - Changelog

## Summary

Extended MOAD to include comprehensive MySQL observability for both `schoolsoft` and `permissionMan` databases, covering performance monitoring and application-level analytics.

## Changes Made

### 1. Docker Compose Configuration

**File:** `docker-compose.yml`

- Updated MySQL exporter to use configurable user via `MYSQL_MOAD_RO_USER` (default: `moad_ro`) instead of generic `exporter` user
- Changed environment variable from `MYSQL_EXPORTER_PASSWORD` to `MYSQL_MOAD_RO_PASSWORD`
- Added `MYSQL_MOAD_RO_USER` environment variable for configurable MySQL username
- Added documentation comments about read-only access model

### 2. Prometheus Configuration

**File:** `prometheus/prometheus.yml`

- Enhanced MySQL scrape config with labels for database cluster identification
- Added `databases: 'schoolsoft,permissionMan'` label
- Improved instance labeling

### 3. Vector Configuration

**File:** `vector/vector.yml`

**Added Event Types:**
- `form`: PermissionMan form events (distribution, completion, etc.)
- `integration_task`: Integration task events (full/delta)

**New Extracted Identifiers:**
- `form_id` → `permissionMan.Form.id`
- `user_form_id` → `permissionMan.UserForm.id`
- `district_id` → `permissionMan.District.id`
- `integration_task_id` → `permissionMan.FullIntegrationTask.id` / `DeltaIntegrationTask.id`
- `form_action`: distributed, completed, submitted, expired, archived, etc.
- `form_status`: Current form status
- `integration_type`: full, delta, incremental
- `integration_status`: success, failed, error, completed, running, pending

**Enhanced Join Hints:**
- Added permissionMan schema join hints to `mysql_joins` array
- Supports joins with both `schoolsoft` and `permissionMan` schemas

### 4. Grafana Dashboards

#### MySQL Performance Dashboard
**File:** `grafana/dashboards/mysql-performance.json`

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

**Annotations:**
- High Connection Usage (>80%)
- Low Buffer Pool Hit Ratio (<95%)

#### PermissionMan Analytics Dashboard
**File:** `grafana/dashboards/permissionman-analytics.json`

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

#### Correlation Dashboard
**File:** `grafana/dashboards/correlation-dashboard.json`

**Panels:**
- Authentication Failures vs MySQL Threads
- Application Requests vs MySQL Query Rate
- PowerSchool Integration vs Slow Queries
- Form Activity vs Database Load
- Email Delivery vs Notification Queue
- Conference Activity vs Database Connections
- InnoDB Buffer Pool Hit Ratio vs Query Rate
- Root Cause Analysis - Event Timeline

**Annotations:**
- Database Saturation (>90% connections)
- High Lock Contention (>10 waits/sec)

### 5. Documentation

#### New Documentation
**File:** `docs/MYSQL_MONITORING.md`

Comprehensive guide covering:
- MySQL exporter configuration
- Performance metrics explanation
- Application analytics for permissionMan
- Dashboard descriptions
- Log integration
- Security considerations
- Alerting recommendations
- Troubleshooting guide
- Best practices

#### Updated Documentation

**README.md:**
- Added MySQL Monitoring section
- Added Form Events and Integration Task Events to Event Taxonomy
- Added MYSQL_MONITORING.md to documentation list

**QUICK_START.md:**
- Updated environment variable from `MYSQL_EXPORTER_PASSWORD` to `MYSQL_MOAD_RO_PASSWORD`
- Added note about `moad_ro` user

**DEPLOYMENT_CHECKLIST.md:**
- Updated environment variable name
- Added detailed MySQL user requirements
- Added `permissionMan` database requirement
- Added `performance_schema` requirement

## MySQL User Requirements

### User: Configurable via `MYSQL_MOAD_RO_USER` (default: `moad_ro`)

**Required Grants:**
```sql
-- Replace 'moad_ro' with your actual username (from MYSQL_MOAD_RO_USER) if different
GRANT SELECT ON schoolsoft.* TO 'moad_ro'@'%';
GRANT SELECT ON permissionMan.* TO 'moad_ro'@'%';
GRANT SELECT ON performance_schema.* TO 'moad_ro'@'%';
GRANT SELECT ON information_schema.* TO 'moad_ro'@'%';
```

**Explicitly Denied:**
- No access to `mysql.*` system database
- No `SUPER` privilege
- No `PROCESS` privilege
- No `RELOAD` privilege
- No `EVENT` privilege
- No `REPLICATION CLIENT` privilege

## Deployment Notes

### Environment Variables

Update `.env` file:
```bash
MYSQL_MOAD_RO_USER=moad_ro
MYSQL_MOAD_RO_PASSWORD=your_moad_ro_password
```

### MySQL Configuration

1. Create MySQL user (from `MYSQL_MOAD_RO_USER`) with read-only grants
2. Ensure `performance_schema` is enabled
3. Update `docker-compose.yml` line 56 with actual MySQL hostname/IP
4. Verify both `schoolsoft` and `permissionMan` databases exist

### Verification

After deployment:
1. Check MySQL exporter: `docker logs moad-mysqld-exporter`
2. Verify Prometheus targets: http://localhost:9090/targets
3. Check Grafana dashboards load correctly
4. Verify metrics appear in Prometheus: http://localhost:9090/graph?g0.expr=mysql_up

## Breaking Changes

### Environment Variable Rename

**Before:**
```bash
MYSQL_EXPORTER_PASSWORD=...
```

**After:**
```bash
MYSQL_MOAD_RO_PASSWORD=...
```

Update your `.env` file accordingly.

## New Capabilities

1. **Performance Monitoring**: Comprehensive InnoDB, query, and connection metrics
2. **Application Analytics**: Form lifecycle, integration tasks, notification queues
3. **Correlation**: Unified view of logs, metrics, and database performance
4. **PermissionMan Support**: First-class support for permissionMan schema analytics
5. **Join Compatibility**: Extended join hints for permissionMan tables

## Files Added

- `grafana/dashboards/mysql-performance.json`
- `grafana/dashboards/permissionman-analytics.json`
- `grafana/dashboards/correlation-dashboard.json`
- `docs/MYSQL_MONITORING.md`
- `CHANGELOG_MYSQL_MONITORING.md` (this file)

## Files Modified

- `docker-compose.yml`
- `prometheus/prometheus.yml`
- `vector/vector.yml`
- `README.md`
- `QUICK_START.md`
- `DEPLOYMENT_CHECKLIST.md`

