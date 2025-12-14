# MOAD Join Compatibility Design

## Overview

The MOAD (Mother Of All Dashboards) stack is designed to ensure all log-derived identifiers are **join-compatible** with the MySQL `schoolsoft` database schema. This enables unified analytics across logs, metrics, and relational data.

## Design Principles

### 1. Identifier Normalization

All identifiers extracted from logs are normalized to match MySQL column formats:

- **Integer IDs**: Converted to integers (not strings) for direct joins
- **String Identifiers**: Lowercased and trimmed for case-insensitive matching
- **Email Addresses**: Normalized to lowercase, trimmed whitespace
- **Usernames**: Email domains stripped when present, normalized to match `users.userName`

### 2. Type Safety

- Invalid identifiers become `null` (not `0` or empty strings)
- Type coercion happens at ingestion time (Vector transforms)
- MySQL join operations are type-safe

### 3. Join Hints

Each log event includes metadata indicating which MySQL columns can be joined:

```json
{
  "mysql_joins": ["users.id", "users.userName", "schools.id"],
  "mysql_join_user_id": 12345,
  "mysql_join_user_name": "jdoe",
  "mysql_join_school_id": 678
}
```

## Identifier Extraction Strategy

### Authentication Events

**Sources:** Tomcat logs, HAProxy logs

**Extracted Identifiers:**
- `username` → Normalized to `users.userName`
- `email` → Normalized to `users.email`
- `user_id` → Integer for `users.id` join
- `client_ip` → For `users.lastKnownIP` correlation
- `school_id` → Integer for `schools.id` join

**Join Path:**
```
Log Event → users.userName → users.id → users.schoolId → schools.id
```

### PowerSchool Integration Events

**Sources:** Tomcat ConsumerManager logs

**Extracted Identifiers:**
- `email` → `parents.email` or `users.email`
- `student_ids[]` → Array of `students.id` values
- `school_id` → `schools.id`

**Join Path:**
```
Log Event → parents.email → parents.userId → users.id
Log Event → student_ids[] → students.id → studentSchool.schoolId → schools.id
```

### Email Events

**Sources:** Postfix logs

**Extracted Identifiers:**
- `recipient_email` → `users.email` or `parents.email`
- `sender_email` → `users.email` (if notifications@schoolsoft.com)
- `message_id` → Correlation identifier

**Join Path:**
```
Log Event → recipient_email → users.email → users.id → users.schoolId → schools.id
Log Event → recipient_email → parents.email → parents.userId → users.id
```

### HTTP Traffic Events

**Sources:** HAProxy logs

**Extracted Identifiers:**
- `school_subdomain` → Lookup to `schools.subdomain` → `schools.id`
- `school_id` → Direct `schools.id` join (if in URL)
- `client_ip` → For geo/IP analysis

## Vector Transform Pipeline

The Vector configuration implements a multi-stage transform pipeline:

1. **Source Ingestion**: Read-only log file reading
2. **Multiline Reconstruction**: Reconstruct stack traces and multi-line events
3. **Event Classification**: Identify event types (auth, PowerSchool, email, HTTP)
4. **Identifier Extraction**: Extract and normalize identifiers using regex patterns
5. **Type Conversion**: Convert strings to integers for ID fields
6. **Join Hint Generation**: Add `mysql_joins` metadata
7. **Output**: Send to Loki and write structured JSON files

## MySQL Schema Compatibility

### Core Tables

| Table | Primary Join Column | Log Field Mapping |
|-------|---------------------|-------------------|
| `users` | `id` (INT) | `mysql_join_user_id` |
| `users` | `userName` (VARCHAR) | `mysql_join_user_name` |
| `users` | `email` (VARCHAR) | `mysql_join_user_email` |
| `schools` | `id` (INT) | `mysql_join_school_id` |
| `students` | `id` (INT) | `mysql_join_student_id` |
| `parents` | `email` (VARCHAR) | `mysql_join_user_email` |
| `parents` | `userId` (INT) | `mysql_join_user_id` (via users) |

### Relationship Traversal

The design supports multi-hop joins:

```
Log Event
  → users.userName → users.id
  → users.schoolId → schools.id
  → schools.districtId → district.id
```

## Grafana Integration

### LogQL Queries with Join Hints

Grafana dashboards can use LogQL to query logs and leverage join hints:

```logql
{event_type="authentication", auth_result="failed"} 
| json 
| mysql_join_school_id != ""
| rate() by (school_id)
```

### Prometheus Metrics Correlation

MySQL metrics from `mysqld-exporter` can be correlated with log events:

- Auth failures vs `mysql_threads_connected`
- PowerSchool sync vs `mysql_slow_queries`
- Conference booking spikes vs `mysql_innodb_row_lock_time`

## Validation and Quality Assurance

### Join Compatibility Flag

Every log event includes:
```json
{
  "moad_join_compatible": true,
  "moad_version": "1.0"
}
```

This flag indicates:
- Identifiers were successfully extracted
- Type conversions completed
- Join hints are available

### Missing Identifier Handling

- Missing identifiers are set to `null` (not empty strings)
- Events with missing identifiers are still processed
- Dashboards can filter for events with specific join capabilities

## Example Use Cases

### 1. Authentication Failures by School

**Query:**
```logql
{event_type="authentication", auth_result="failed"} 
| json 
| mysql_join_school_id != ""
| rate() by (school_id)
```

**Join:** `mysql_join_school_id` → `schools.id` → `schools.name`

### 2. PowerSchool Integration Success Rate

**Query:**
```logql
{event_type="powerschool_integration"} 
| json 
| mysql_join_school_id != ""
| rate() by (school_id, integration_status)
```

**Join:** `mysql_join_school_id` → `schools.id` → `schools.name`

### 3. Email Delivery by User School

**Query:**
```logql
{event_type="email", email_outcome="sent"} 
| json 
| mysql_join_user_email != ""
```

**Join:** `mysql_join_user_email` → `users.email` → `users.schoolId` → `schools.name`

### 4. Database Stress Correlation

**Metrics Query:**
```promql
mysql_threads_connected
```

**Log Query:**
```logql
{event_type="authentication"} 
| json 
| rate() by (auth_result)
```

**Correlation:** Time-series alignment of metrics and logs

## Best Practices

### 1. Prefer Integer IDs

When available, use integer IDs (`user_id`, `school_id`) over string identifiers for joins. They're:
- Faster to join
- More reliable (no normalization issues)
- Type-safe

### 2. Use Join Hints

Always check `mysql_joins` array to see what joins are available for an event before constructing queries.

### 3. Handle Missing Identifiers

Not all events will have all identifiers. Design dashboards to:
- Show events with available joins
- Indicate when joins are not possible
- Provide fallback visualizations

### 4. Validate Normalization

Regularly verify that extracted identifiers match MySQL values:
- Sample log events
- Compare `mysql_join_user_name` with `users.userName`
- Verify integer conversions are correct

## Troubleshooting

### Identifiers Not Joining

1. Check normalization: Are strings lowercased? Are IDs integers?
2. Verify extraction: Are regex patterns matching log formats?
3. Check join hints: Does `mysql_joins` array include the expected column?

### Type Mismatches

1. Ensure Vector transforms convert IDs to integers
2. Verify MySQL column types match log field types
3. Check for null handling (null vs 0 vs empty string)

### Missing Events

1. Verify log file paths in Vector sources
2. Check multiline reconstruction patterns
3. Validate event classification regex patterns

## Future Enhancements

### 1. Lookup Tables

Create Vector lookup tables for:
- `school_subdomain` → `schools.id` mapping
- `username` → `users.id` mapping (for faster joins)

### 2. Enrichment

Enrich log events with MySQL data at ingestion time:
- Add `school_name` from `schools.name`
- Add `user_email` from `users.email`
- Add `district_name` from `district.name`

### 3. Real-time Joins

Implement real-time join capabilities:
- Vector HTTP transform to query MySQL
- Cache lookup results
- Periodic refresh of lookup tables

## Conclusion

The MOAD join compatibility design ensures that all log-derived identifiers are normalized, typed, and annotated for reliable joins with the MySQL schema. This enables unified analytics across logs, metrics, and relational data, fulfilling the core mission of providing a single source of truth for SchoolSoft operations.

