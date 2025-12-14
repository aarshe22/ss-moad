# MOAD Schema Mapping: Log Identifiers to MySQL Joins

This document defines how log-derived identifiers map to MySQL schema columns for join compatibility.

## Core Principle

All identifiers extracted from logs are normalized to match MySQL column types and formats exactly, enabling reliable joins in Grafana dashboards and analytical queries.

## Identifier Mapping Table

### User Identifiers

| Log Field | MySQL Table.Column | Type | Normalization |
|-----------|-------------------|------|---------------|
| `username` | `users.userName` | VARCHAR | Lowercase, email domain stripped if present |
| `username_normalized` | `users.userName` | VARCHAR | Lowercase, no domain |
| `email` | `users.email` | VARCHAR | Lowercase, trimmed |
| `recipient_email` | `users.email` | VARCHAR | Lowercase, trimmed |
| `user_id` | `users.id` | INT | Integer conversion, null if invalid |
| `client_ip` | `users.lastKnownIP` | VARCHAR | Direct match (for correlation) |

**Join Strategy:**
- Primary: `users.id` (most reliable)
- Fallback: `users.userName` (normalized username)
- Fallback: `users.email` (for email-based events)

### School Identifiers

| Log Field | MySQL Table.Column | Type | Normalization |
|-----------|-------------------|------|---------------|
| `school_id` | `schools.id` | INT | Integer conversion, null if invalid |
| `school_subdomain` | `schools.subdomain` | VARCHAR | Lowercase, for lookup (not direct join) |

**Join Strategy:**
- Primary: `schools.id` (direct integer join)
- Lookup: `school_subdomain` → `schools.subdomain` → `schools.id` (requires lookup table)

### Student Identifiers

| Log Field | MySQL Table.Column | Type | Normalization |
|-----------|-------------------|------|---------------|
| `student_id` | `students.id` | INT | Integer conversion, null if invalid |
| `student_ids[]` | `students.id` | INT[] | Array of integers (for PowerSchool fanout) |

**Join Strategy:**
- Direct: `students.id` (single student)
- Array: `student_ids` (multiple students, requires array handling in queries)

### Parent Identifiers

| Log Field | MySQL Table.Column | Type | Normalization |
|-----------|-------------------|------|---------------|
| `email` | `parents.email` | VARCHAR | Lowercase, trimmed |
| `recipient_email` | `parents.email` | VARCHAR | Lowercase, trimmed |
| `user_id` | `parents.userId` | INT | Integer conversion (via users table) |

**Join Strategy:**
- Direct: `parents.email` (for email events)
- Indirect: `parents.userId` → `users.id` (for user-based events)

### District Identifiers

| Log Field | MySQL Table.Column | Type | Normalization |
|-----------|-------------------|------|---------------|
| `district_id` | `district.id` | INT | Integer conversion (derived from school) |

**Join Strategy:**
- Indirect: `schools.id` → `schools.districtId` → `district.id`

## Event-Specific Mappings

### Authentication Events

**Source:** Tomcat, HAProxy logs

**Identifiers Extracted:**
- `username` → `users.userName`
- `email` → `users.email`
- `user_id` → `users.id` (if available in log)
- `client_ip` → `users.lastKnownIP` (correlation)
- `school_id` → `schools.id` (from URL or context)

**Join Path:**
```
logs.username → users.userName → users.id → users.schoolId → schools.id
logs.client_ip → users.lastKnownIP (correlation for security analysis)
```

### PowerSchool Integration Events

**Source:** Tomcat ConsumerManager logs

**Identifiers Extracted:**
- `sis_identity` → External SIS identifier (not directly joinable)
- `email` → `parents.email` or `users.email`
- `student_ids[]` → `students.id[]`
- `school_id` → `schools.id`

**Join Path:**
```
logs.email → parents.email → parents.userId → users.id
logs.student_ids → students.id → studentSchool.schoolId → schools.id
logs.school_id → schools.id
```

### Email Events

**Source:** Postfix logs

**Identifiers Extracted:**
- `recipient_email` → `users.email` or `parents.email`
- `sender_email` → `users.email` (if notifications@schoolsoft.com)
- `message_id` → Correlation identifier

**Join Path:**
```
logs.recipient_email → users.email → users.id → users.schoolId → schools.id
logs.recipient_email → parents.email → parents.userId → users.id
```

### HTTP Traffic Events

**Source:** HAProxy logs

**Identifiers Extracted:**
- `school_subdomain` → `schools.subdomain` (lookup)
- `school_id` → `schools.id` (if in URL)
- `client_ip` → Correlation for geo/IP analysis

**Join Path:**
```
logs.school_subdomain → schools.subdomain → schools.id
logs.school_id → schools.id
```

## Data Type Compatibility

### Integer IDs
- All ID fields (`user_id`, `school_id`, `student_id`) are converted to integers
- Invalid values become `null` (not 0)
- This ensures type compatibility with MySQL INT columns

### String Identifiers
- All string identifiers are lowercased for case-insensitive matching
- Email addresses are trimmed and normalized
- Usernames have email domains stripped when present

### Timestamps
- All timestamps are normalized to ISO 8601 format
- Stored as `@timestamp` field for consistency
- Compatible with Grafana time range queries

## Join Hints in Logs

Each log event includes a `mysql_joins` array field indicating which MySQL columns can be joined:

```json
{
  "mysql_joins": ["users.id", "users.userName", "schools.id"],
  "mysql_join_user_id": 12345,
  "mysql_join_user_name": "jdoe",
  "mysql_join_school_id": 678
}
```

This enables Grafana dashboards to:
1. Identify joinable events
2. Construct appropriate queries
3. Provide join suggestions in UI

## Normalization Rules

### Username Normalization
1. Convert to lowercase
2. If email format (contains @), extract username portion
3. Remove special characters that don't match `users.userName` format

### Email Normalization
1. Convert to lowercase
2. Trim whitespace
3. Validate format (basic regex check)

### ID Normalization
1. Extract numeric value from string
2. Convert to integer
3. Set to `null` if conversion fails (not 0)

### School Subdomain Normalization
1. Convert to lowercase
2. Remove protocol and domain suffixes
3. Extract subdomain from URL patterns

## Example Join Queries

### Authentication Failures by School
```sql
-- Conceptual (Grafana uses LogQL + PromQL, not direct SQL)
-- LogQL query:
{event_type="authentication", auth_result="failed"} 
| json 
| mysql_join_school_id != ""

-- Then join with MySQL metrics or use school_id for grouping
```

### PowerSchool Integration Success Rate
```sql
-- LogQL:
{event_type="powerschool_integration"} 
| json 
| mysql_join_school_id != ""
| rate() by (school_id, integration_status)
```

### Email Delivery by User School
```sql
-- LogQL:
{event_type="email"} 
| json 
| mysql_join_user_email != ""
-- Join hint: users.email → users.schoolId → schools.name
```

## Validation

All log events are validated for join compatibility:
- `moad_join_compatible: true` flag indicates successful normalization
- Missing required identifiers are logged but don't block processing
- Invalid identifiers are set to `null` rather than causing errors

