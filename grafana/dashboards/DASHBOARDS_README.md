# MOAD Grafana Dashboards Guide

## Overview

This directory contains production-ready Grafana dashboards for the MOAD (Mother Of All Dashboards) observability stack. All dashboards use actual labels and fields extracted by Vector from CM, PFM, HAProxy, and Postfix logs.

## Label Structure

### Loki Labels (Indexed for Fast Filtering)

These labels are set by Vector and indexed in Loki for efficient querying:

- **`app`**: Application identifier - `"CM"` or `"PFM"`
- **`host`**: Hostname - `"app1"` or `"app2"`
- **`event_type`**: Event classification - `"authentication"`, `"form"`, `"integration_task"`, `"powerschool_integration"`, `"conference"`, `"policy"`, `"http_traffic"`, `"email"`, `"unknown"`
- **`event_category`**: Event category - `"security"`, `"application"`, `"business"`, `"integration"`, `"infrastructure"`, `"communication"`
- **`source_component`**: Log source - `"tomcat"`, `"haproxy"`, `"postfix"`

### Log Fields (Extracted via `| json`)

These fields are in the JSON log body and extracted using LogQL's `| json`:

- **`username`**, **`username_normalized`**: User identifier (normalized for MySQL joins)
- **`email`**: User email address
- **`school_id`**: School identifier (integer, join-compatible with MySQL)
- **`school_subdomain`**: School subdomain from URL
- **`user_id`**: User ID (integer)
- **`student_id`**: Student ID (integer)
- **`district_id`**: District ID (integer)
- **`form_id`**, **`user_form_id`**: PermissionMan form identifiers
- **`client_ip`**: Client IP address
- **`http_status`**, **`http_method`**, **`http_path`**: HTTP request details
- **`auth_result`**: `"success"`, `"failed"`, or `"unknown"`
- **`level`**: Log level - `"error"`, `"warn"`, `"info"`, `"debug"`, `"unknown"`
- **`device`**: `"mobile"`, `"desktop"`, or `"unknown"`
- **`email_outcome`**: `"sent"`, `"bounced"`, `"deferred"`, `"rejected"`, `"unknown"`
- **`recipient_email`**, **`sender_email`**: Email addresses
- **`message`**: Full log message text

## Dashboard Catalog

### 1. Global Platform Overview (`global-overview.json`)

**Purpose**: Executive-level view of entire platform health

**Key Panels**:
- Service health summary (UP/DOWN status)
- Total request volume (CM + PFM combined)
- Error rate by service
- Authentication failures (last 24h)
- Top 10 schools by error count
- Top 10 users by error count
- System resource saturation (MySQL connections, InnoDB buffer pool)
- Error rate by event category
- HTTP status code distribution

**Variables**: `app`, `host` (multi-select)

**Use Cases**:
- Daily operations review
- Executive reporting
- Incident triage (identify affected services)

### 2. Conference Manager (CM) Dashboard (`cm-dashboard.json`)

**Purpose**: Deep dive into CM application metrics

**Key Panels**:
- CM request rate
- Authentication attempts vs failures
- Session creation failures
- Top CM error types
- Top schools by CM errors
- Top users by CM errors
- HTTP status code distribution
- HTTP 4xx/5xx error rate
- CM error rate over time by category

**Variables**: `host` (multi-select)

**Use Cases**:
- CM-specific troubleshooting
- Authentication issue investigation
- Performance monitoring

### 3. Parent / Family Manager (PFM) Dashboard (`pfm-dashboard.json`)

**Purpose**: Deep dive into PFM application metrics

**Key Panels**:
- PFM request rate
- Login success vs failure
- Account lockouts
- Password reset errors
- Top PFM error messages
- Top schools by PFM errors
- Top users by PFM errors
- HTTP status distribution
- PFM error rate by category

**Variables**: `host` (multi-select)

**Use Cases**:
- PFM-specific troubleshooting
- User account issue investigation
- Parent portal monitoring

### 4. HAProxy Dashboard (`haproxy-dashboard.json`)

**Purpose**: Traffic and load balancing metrics

**Key Panels**:
- Frontend request rate
- HTTP 4xx / 5xx rates
- HTTP status code distribution
- Top client IPs by error rate
- Device type distribution
- HTTP method distribution
- Request rate by school subdomain
- Connection errors

**Variables**: `app`, `host` (multi-select)

**Use Cases**:
- Traffic pattern analysis
- Load balancing health
- DDoS detection (top client IPs)
- Device usage analytics

### 5. Postfix Dashboard (`postfix-dashboard.json`)

**Purpose**: Email delivery and flow monitoring

**Key Panels**:
- Messages received/sent
- Email outcome distribution (sent, bounced, deferred, rejected)
- Deferred messages count
- Bounce rate
- Top sender domains
- Top recipient domains
- Email outcome rate over time

**Variables**: `app`, `host` (multi-select)

**Use Cases**:
- Email delivery troubleshooting
- Bounce rate monitoring
- Email queue health
- Domain reputation tracking

### 6. Authentication Correlation (`authentication-correlation.json`)

**Purpose**: Cross-service authentication failure analysis

**Key Panels**:
- Auth failures by service (CM vs PFM)
- Auth failures by school
- Auth failures by user
- Auth failures by client IP
- Timeline correlation across services (with MySQL threads)
- Top error messages related to auth

**Variables**: `school_id`, `username` (multi-select filters)

**Use Cases**:
- Security incident investigation
- Brute force detection
- Account compromise analysis
- Cross-service correlation

### 7. School-Centric Error Analysis (`school-focus.json`)

**Purpose**: Drill-down analysis for specific schools

**Key Panels**:
- Errors by service for selected school
- Auth failures for selected school
- Top users within school by errors
- Error categories for selected school
- Historical error trends (7 days, 30 days)
- Event types for selected school

**Variables**: `school_id` (single-select dropdown)

**Use Cases**:
- School-specific troubleshooting
- District reporting
- School performance analysis
- Historical trend analysis

### 8. User / Student Error Analysis (`user-focus.json`)

**Purpose**: Drill-down analysis for specific users

**Key Panels**:
- Errors by service for user
- Auth failures over time
- Client IP history
- Error types for user
- Session lifecycle anomalies
- Last known successful login
- User activity timeline

**Variables**: `username` (single-select dropdown)

**Use Cases**:
- User support troubleshooting
- Account security investigation
- Session issue diagnosis
- User behavior analysis

### 9. Top Errors & Offenders (`top-offenders.json`)

**Purpose**: Identify patterns and recurring issues

**Key Panels**:
- Top error types (all services)
- Top users by error count
- Top schools by error count
- Top client IPs causing errors
- Error spikes over time
- Recurring vs transient errors
- Error rate by event category

**Variables**: `time_range` (1h, 6h, 12h, 24h, 7d, 30d)

**Use Cases**:
- Pattern identification
- Recurring issue detection
- Executive reporting
- Incident prioritization

### 10. MySQL Performance (`mysql-performance.json`)

**Purpose**: Database health and performance (existing dashboard)

**Key Panels**:
- MySQL up status
- Threads connected vs max
- InnoDB buffer pool utilization
- Query latency (p95/p99)
- Lock waits
- Connection saturation
- Schema growth

**Use Cases**:
- Database performance monitoring
- Capacity planning
- Query optimization
- Connection pool management

### 11. PermissionMan Analytics (`permissionman-analytics.json`)

**Purpose**: PermissionMan application-level analytics (existing dashboard)

**Key Panels**:
- Form lifecycle metrics
- Per-school/district activity
- UserFormAudit actions
- Integration task monitoring
- Growth trends

**Use Cases**:
- Business analytics
- Form usage patterns
- Integration health
- Growth analysis

### 12. Correlation Dashboard (`correlation-dashboard.json`)

**Purpose**: Cross-layer correlation (existing dashboard)

**Key Panels**:
- Authentication failures vs MySQL threads
- Error rate vs database load
- User activity vs system performance

**Use Cases**:
- Root cause analysis
- Performance correlation
- Capacity planning

### 13. Authentication Failures (`authentication-failures.json`)

**Purpose**: Security-focused authentication monitoring (existing dashboard)

**Key Panels**:
- Auth failure trends
- Failed login attempts
- Account lockout events

**Use Cases**:
- Security monitoring
- Brute force detection
- Account security

## Dashboard Navigation & Drill-Down

### Recommended Navigation Flow

1. **Start**: Global Platform Overview
   - Identify affected services
   - Identify top offenders (schools, users)

2. **Service-Level**: CM or PFM Dashboard
   - Deep dive into specific application
   - Identify error patterns

3. **Drill-Down**: School-Centric or User-Centric
   - Focus on specific school or user
   - Historical trend analysis

4. **Correlation**: Authentication Correlation or Correlation Dashboard
   - Cross-service analysis
   - Root cause identification

5. **Infrastructure**: HAProxy, Postfix, MySQL Performance
   - Infrastructure-level issues
   - Resource saturation

### Linking Between Dashboards

Dashboards are designed to work together:

- **Global Overview** → **CM/PFM Dashboards** (via `app` variable)
- **Top Offenders** → **School-Centric** (select school_id from table)
- **Top Offenders** → **User-Centric** (select username from table)
- **Authentication Correlation** → **User-Centric** (select username)
- **School-Centric** → **User-Centric** (drill down to specific user)

## Query Patterns

### LogQL Query Structure

All LogQL queries follow this pattern:

```logql
{label_filters} | json [time_range]
```

**Examples**:

```logql
# Error rate by service
sum(rate({app="CM", level="error"} | json [5m])) by (app)

# Top schools by errors
topk(10, sum by (school_id) (count_over_time({level="error", school_id!=""} | json [1h])))

# Auth failures
sum(rate({event_type="authentication", auth_result="failed"} | json [5m]))
```

### PromQL Query Structure

For MySQL and infrastructure metrics:

```promql
# MySQL connections
mysql_global_status_threads_connected

# Connection pool utilization
mysql_global_status_threads_connected / mysql_global_variables_max_connections * 100
```

## Label Best Practices

### When to Use Labels vs Fields

**Use Labels** (indexed, fast filtering):
- `app`, `host`, `event_type`, `event_category`, `source_component`
- High cardinality is OK for these (limited values)

**Use Fields** (extracted via `| json`):
- `username`, `school_id`, `client_ip`, `http_status`
- High cardinality fields (many unique values)
- Extracted on-demand for filtering

### Filtering Best Practices

1. **Always filter by labels first** (fast):
   ```logql
   {app="CM", level="error"} | json
   ```

2. **Then filter by fields** (slower, but necessary):
   ```logql
   {app="CM"} | json | school_id="123"
   ```

3. **Use `!=""` to exclude null values**:
   ```logql
   {school_id!=""} | json
   ```

## Operational Use Cases

### Incident Response

1. **Alert fires** → Check Global Overview
2. **Identify service** → Open CM or PFM dashboard
3. **Identify scope** → Check Top Offenders
4. **Drill down** → School-Centric or User-Centric
5. **Correlate** → Authentication Correlation or Correlation Dashboard
6. **Check infrastructure** → HAProxy, Postfix, MySQL Performance

### Daily Operations

1. **Morning review**: Global Overview
2. **Service health**: CM/PFM dashboards
3. **Email health**: Postfix dashboard
4. **Traffic patterns**: HAProxy dashboard
5. **Database health**: MySQL Performance

### Security Investigation

1. **Authentication Correlation**: Identify patterns
2. **User-Centric**: Investigate specific user
3. **HAProxy**: Check client IP patterns
4. **Top Offenders**: Identify attack patterns

## Troubleshooting

### No Data in Panels

1. **Check label values**: Verify labels exist in Loki
   ```logql
   label_values(app)
   label_values({app="CM"}, host)
   ```

2. **Check field extraction**: Verify fields are in JSON
   ```logql
   {app="CM"} | json | line_format "{{.username}}"
   ```

3. **Check time range**: Ensure data exists for selected time range

4. **Check filters**: Verify variable filters aren't excluding all data

### Slow Queries

1. **Add label filters**: Always filter by labels first
2. **Reduce time range**: Use shorter ranges for instant queries
3. **Use rate()**: For time series, use `rate()` instead of `count_over_time()`
4. **Limit topk()**: Use reasonable limits (10-20) for topk()

### Missing Labels

If a label doesn't appear in dropdowns:

1. **Check Vector config**: Ensure label is set in `vector.yml` Loki sink
2. **Check log ingestion**: Verify logs are being ingested
3. **Wait for indexing**: New labels may take time to appear in Loki

## Dashboard Customization

### Adding New Panels

1. Use existing panels as templates
2. Follow LogQL query patterns above
3. Use consistent color schemes (green/yellow/red for thresholds)
4. Add descriptions explaining what the panel shows

### Adding New Variables

1. Use `label_values()` for Loki labels
2. Use `query_result()` for derived values
3. Set appropriate defaults (All, empty, or specific value)
4. Enable `includeAll` for multi-select variables

### Color Coding

- **Green**: Healthy, normal operation
- **Yellow**: Warning, approaching threshold
- **Red**: Critical, threshold exceeded
- **Blue**: Informational, neutral

## Version Information

- **MOAD Version**: 0.91
- **Grafana Version**: 12.3.0
- **Loki Version**: 2.9.0
- **Vector Version**: 0.40.0-alpine
- **Dashboard Schema**: 38

## Support

For issues or questions:
1. Check Vector logs: `docker logs moad-vector`
2. Check Loki logs: `docker logs moad-loki`
3. Verify label extraction: Query Loki directly
4. Review Vector configuration: `vector/vector.yml`

