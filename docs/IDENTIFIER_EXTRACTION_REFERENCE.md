# Identifier Extraction Reference

Quick reference for log identifier extraction patterns and MySQL join mappings.

## Authentication Events

### Source Patterns
- Tomcat: `catalina.out` logs
- HAProxy: Access logs with login paths

### Extracted Fields

| Field | Regex Pattern | MySQL Join | Normalization |
|-------|---------------|------------|---------------|
| `username` | `(?:user\|username\|login)[\s:=]+([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\|[a-zA-Z0-9._-]+)` | `users.userName` | Lowercase, strip email domain |
| `email` | `([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})` | `users.email` | Lowercase |
| `user_id` | `(?:user\|userId)[\s:=]+(\d+)` | `users.id` | Integer |
| `client_ip` | `\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b` | `users.lastKnownIP` | Direct match |
| `school_id` | `(?:school\|schoolId)[\s:=]+(\d+)` | `schools.id` | Integer |
| `school_subdomain` | `https?://([a-z0-9-]+)\.schoolsoft\.(?:net\|com)` | `schools.subdomain` | Lowercase |

### Example Log Line
```
2024-01-15 10:30:45 INFO User login successful: username=jdoe@example.com, schoolId=123, IP=192.168.1.100
```

### Extracted JSON
```json
{
  "event_type": "authentication",
  "username": "jdoe@example.com",
  "username_normalized": "jdoe",
  "email": "jdoe@example.com",
  "user_id": null,
  "client_ip": "192.168.1.100",
  "school_id": 123,
  "auth_result": "success",
  "mysql_join_user_name": "jdoe",
  "mysql_join_user_email": "jdoe@example.com",
  "mysql_join_school_id": 123,
  "mysql_joins": ["users.userName", "users.email", "schools.id"]
}
```

## PowerSchool Integration Events

### Source Patterns
- Tomcat: ConsumerManager logs

### Extracted Fields

| Field | Regex Pattern | MySQL Join | Normalization |
|-------|---------------|------------|---------------|
| `sis_identity` | `(?:sis\|external\|powerschool)[\s:=]+([a-zA-Z0-9._-]+)` | N/A | External identifier |
| `email` | `([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})` | `parents.email` | Lowercase |
| `student_ids` | `(?:student\|studentId)[\s:=]+(\d+)` | `students.id` | Integer array |
| `school_id` | `(?:school\|schoolId)[\s:=]+(\d+)` | `schools.id` | Integer |
| `integration_status` | `(?i)(success\|failed\|error\|completed)` | N/A | Status string |

### Example Log Line
```
2024-01-15 10:30:45 INFO PowerSchool sync completed: email=parent@example.com, students=[456, 789], schoolId=123, status=success
```

### Extracted JSON
```json
{
  "event_type": "powerschool_integration",
  "sis_identity": null,
  "email": "parent@example.com",
  "student_ids": [456, 789],
  "school_id": 123,
  "integration_status": "success",
  "mysql_join_user_email": "parent@example.com",
  "mysql_join_student_id": null,
  "mysql_join_school_id": 123,
  "mysql_joins": ["parents.email", "schools.id", "students.id"]
}
```

## Email Events

### Source Patterns
- Postfix: `mail.log`

### Extracted Fields

| Field | Regex Pattern | MySQL Join | Normalization |
|-------|---------------|------------|---------------|
| `recipient_email` | `to=<([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>` | `users.email` | Lowercase |
| `sender_email` | `from=<([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>` | `users.email` | Lowercase |
| `message_id` | `message-id=<([^>]+)>` | N/A | Correlation ID |
| `email_outcome` | `(?i)(sent\|bounced\|deferred\|rejected)` | N/A | Status string |

### Example Log Line
```
Jan 15 10:30:45 postfix/smtp[12345]: ABC123: to=<user@example.com>, status=sent
```

### Extracted JSON
```json
{
  "event_type": "email",
  "recipient_email": "user@example.com",
  "sender_email": "notifications@schoolsoft.com",
  "message_id": "ABC123",
  "email_outcome": "sent",
  "mysql_join_user_email": "user@example.com",
  "mysql_joins": ["users.email"]
}
```

## HTTP Traffic Events

### Source Patterns
- HAProxy: Access logs

### Extracted Fields

| Field | Regex Pattern | MySQL Join | Normalization |
|-------|---------------|------------|---------------|
| `client_ip` | Apache log format | N/A | Direct match |
| `http_method` | Apache log format | N/A | Uppercase |
| `http_path` | Apache log format | N/A | URL path |
| `http_status` | Apache log format | N/A | Status code |
| `school_subdomain` | `/([a-z0-9-]+)/` | `schools.subdomain` | Lowercase |
| `school_id` | `(?:school\|schoolId)[\s:=/]+(\d+)` | `schools.id` | Integer |
| `device` | User-Agent parsing | N/A | "mobile" or "desktop" |

### Example Log Line
```
192.168.1.100 - - [15/Jan/2024:10:30:45 +0000] "GET /myschool/dashboard HTTP/1.1" 200 1234 "Mozilla/5.0..."
```

### Extracted JSON
```json
{
  "event_type": "http_traffic",
  "client_ip": "192.168.1.100",
  "http_method": "GET",
  "http_path": "/myschool/dashboard",
  "http_status": "200",
  "school_subdomain": "myschool",
  "school_id": null,
  "device": "desktop",
  "mysql_join_school_id": null,
  "mysql_joins": []
}
```

## Conference Events

### Source Patterns
- Tomcat: Application logs

### Extracted Fields

| Field | Regex Pattern | MySQL Join | Normalization |
|-------|---------------|------------|---------------|
| `user_id` | `(?:user\|userId)[\s:=]+(\d+)` | `users.id` | Integer |
| `school_id` | `(?:school\|schoolId)[\s:=]+(\d+)` | `schools.id` | Integer |
| `student_id` | `(?:student\|studentId)[\s:=]+(\d+)` | `students.id` | Integer |

### Example Log Line
```
2024-01-15 10:30:45 INFO Conference scheduled: userId=12345, studentId=67890, schoolId=123
```

### Extracted JSON
```json
{
  "event_type": "conference",
  "user_id": 12345,
  "student_id": 67890,
  "school_id": 123,
  "mysql_join_user_id": 12345,
  "mysql_join_student_id": 67890,
  "mysql_join_school_id": 123,
  "mysql_joins": ["users.id", "students.id", "schools.id"]
}
```

## Normalization Rules Summary

### Username Normalization
1. Extract from log using regex
2. Convert to lowercase: `downcase(.username)`
3. Strip email domain: `replace(.username, r'@.*$', "")`
4. Store in `username_normalized` and `mysql_join_user_name`

### Email Normalization
1. Extract from log using regex
2. Convert to lowercase: `downcase(.email)`
3. Trim whitespace (handled by regex)
4. Store in `mysql_join_user_email`

### ID Normalization
1. Extract numeric value from string: `match(.message, r'(\d+)')`
2. Convert to integer: `to_int(.id)`
3. Set to `null` if conversion fails (not `0`)
4. Store in `mysql_join_*_id` fields

### School Subdomain Normalization
1. Extract from URL: `match(.http_path, r'/([a-z0-9-]+)/')`
2. Convert to lowercase: `downcase(.school_subdomain)`
3. Use for lookup (not direct join - requires lookup table)

## Join Hint Generation

Join hints are automatically generated based on available identifiers:

```vrl
.mysql_joins = []
if .mysql_join_user_id {
  .mysql_joins = append(.mysql_joins, "users.id")
}
if .mysql_join_user_name {
  .mysql_joins = append(.mysql_joins, "users.userName")
}
if .mysql_join_user_email {
  .mysql_joins = append(.mysql_joins, "users.email")
}
if .mysql_join_school_id {
  .mysql_joins = append(.mysql_joins, "schools.id")
}
if .mysql_join_student_id {
  .mysql_joins = append(.mysql_joins, "students.id")
}
```

## Testing Extraction Patterns

### Test Username Extraction
```bash
echo "User login: username=jdoe@example.com" | \
  vector vrl --input-stdin 'match(.input, r"(?:user|username|login)[\s:=]+([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|[a-zA-Z0-9._-]+)")'
```

### Test Email Extraction
```bash
echo "Email sent to user@example.com" | \
  vector vrl --input-stdin 'match(.input, r"([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})")'
```

### Test ID Extraction
```bash
echo "schoolId=123" | \
  vector vrl --input-stdin 'match(.input, r"(?:school|schoolId)[\s:=]+(\d+)")'
```

## Common Patterns

### Pattern: Extract Multiple IDs
```vrl
.student_ids = match(.message, r'(?:student|studentId)[\s:=]+(\d+)') ?? []
if is_string(.student_ids) {
  .student_ids = [.student_ids]
}
.student_ids = map(.student_ids, |id| { to_int(id) ?? null })
```

### Pattern: Extract from URL
```vrl
.school_subdomain = match(.http_path, r'/([a-z0-9-]+)/') ?? null
.school_id = match(.http_path, r'(?:school|schoolId)[\s:=/]+(\d+)') ?? null
```

### Pattern: Case-Insensitive Matching
```vrl
.auth_result = match(.message, r'(?i)(success|successful|failed|failure)') ?? "unknown"
```

## Troubleshooting

### Pattern Not Matching
1. Check regex syntax (Vector uses Rust regex)
2. Verify log format matches expected pattern
3. Test pattern with sample log line
4. Check for special characters that need escaping

### Wrong Normalization
1. Verify normalization order (lowercase before domain strip)
2. Check for edge cases (empty strings, null values)
3. Validate against MySQL column values

### Missing Join Hints
1. Verify identifier extraction succeeded
2. Check join hint generation logic
3. Ensure `moad_join_compatible` flag is set

