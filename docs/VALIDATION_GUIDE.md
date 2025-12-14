# MOAD Join Compatibility Validation Guide

This guide helps validate that log-derived identifiers are correctly normalized and join-compatible with the MySQL schema.

## Validation Checklist

### 1. Vector Configuration Validation

#### Check Identifier Extraction
```bash
# View Vector logs to verify transforms are working
docker logs moad-vector | grep "mysql_join"
```

Expected output should show events with join hints:
```
mysql_join_user_id=12345
mysql_join_school_id=678
mysql_joins=["users.id", "schools.id"]
```

#### Verify Structured Logs
```bash
# Check structured log output
cat /data/moad/logs/structured/*.jsonl | jq 'select(.mysql_joins != null) | {event_type, mysql_joins, mysql_join_user_id, mysql_join_school_id}' | head -20
```

Expected: All events should have `moad_join_compatible: true` and appropriate `mysql_joins` array.

### 2. Identifier Normalization Validation

#### Username Normalization
```bash
# Extract usernames from logs
cat /data/moad/logs/structured/*.jsonl | jq 'select(.username) | {username, username_normalized, mysql_join_user_name}' | head -10
```

Validation:
- ✅ All usernames are lowercase
- ✅ Email-style usernames have domain stripped in `username_normalized`
- ✅ `mysql_join_user_name` matches `username_normalized`

#### Email Normalization
```bash
# Extract emails from logs
cat /data/moad/logs/structured/*.jsonl | jq 'select(.email or .recipient_email) | {email, recipient_email, mysql_join_user_email}' | head -10
```

Validation:
- ✅ All emails are lowercase
- ✅ No leading/trailing whitespace
- ✅ `mysql_join_user_email` matches normalized email

#### ID Type Validation
```bash
# Check ID field types
cat /data/moad/logs/structured/*.jsonl | jq 'select(.user_id or .school_id) | {user_id, school_id, mysql_join_user_id, mysql_join_school_id}' | head -10
```

Validation:
- ✅ All ID fields are integers (not strings)
- ✅ Invalid IDs are `null` (not `0`)
- ✅ `mysql_join_*_id` fields match source IDs

### 3. MySQL Join Compatibility Test

#### Sample Query: Authentication Events
```sql
-- In MySQL, verify that log usernames can join
SELECT 
    u.id,
    u.userName,
    u.email,
    u.schoolId,
    s.name as school_name
FROM users u
LEFT JOIN schools s ON u.schoolId = s.id
WHERE u.userName IN (
    -- Sample usernames from logs (normalized)
    'jdoe',
    'parent123',
    'teacher456'
)
LIMIT 10;
```

#### Sample Query: School Correlation
```sql
-- Verify school_id joins work
SELECT 
    s.id,
    s.name,
    s.subdomain,
    COUNT(DISTINCT u.id) as user_count
FROM schools s
LEFT JOIN users u ON u.schoolId = s.id
WHERE s.id IN (
    -- Sample school IDs from logs
    1, 2, 3, 4, 5
)
GROUP BY s.id, s.name, s.subdomain;
```

### 4. Grafana Dashboard Validation

#### Test Authentication Dashboard
1. Navigate to Grafana: http://dev1.schoolsoft.net:3000
2. Open "Authentication Failures by School" dashboard
3. Verify:
   - ✅ Queries return data
   - ✅ School IDs are displayed correctly
   - ✅ Time series show expected patterns
   - ✅ Log panels show events with join hints

#### Test LogQL Queries
```logql
# Test 1: Events with join hints
{event_type="authentication"} | json | mysql_joins != ""

# Test 2: Filter by school_id
{event_type="authentication"} | json | mysql_join_school_id = "123"

# Test 3: Join-compatible events only
{event_type="authentication"} | json | moad_join_compatible = "true"
```

### 5. Event Classification Validation

#### Verify Event Types
```bash
# Count events by type
cat /data/moad/logs/structured/*.jsonl | jq -r '.event_type' | sort | uniq -c
```

Expected event types:
- `authentication`
- `powerschool_integration`
- `email`
- `http_traffic`
- `conference`
- `policy`

#### Verify Event Categories
```bash
# Count events by category
cat /data/moad/logs/structured/*.jsonl | jq -r '.event_category' | sort | uniq -c
```

Expected categories:
- `security`
- `integration`
- `communication`
- `infrastructure`
- `business`
- `application`

### 6. Join Hint Completeness

#### Check Join Hint Coverage
```bash
# Events with at least one join hint
cat /data/moad/logs/structured/*.jsonl | jq 'select(.mysql_joins != null and (.mysql_joins | length) > 0)' | jq -s 'length'

# Events without join hints (should be minimal)
cat /data/moad/logs/structured/*.jsonl | jq 'select(.mysql_joins == null or (.mysql_joins | length) == 0)' | jq -s 'length'
```

Target: >90% of events should have at least one join hint.

### 7. Real-World Join Test

#### Test Case: Auth Failure → User → School
1. Generate a test authentication failure event
2. Verify it appears in Loki with:
   - `event_type="authentication"`
   - `auth_result="failed"`
   - `mysql_join_user_name` or `mysql_join_user_id`
   - `mysql_join_school_id`
3. In Grafana, create a query that:
   - Filters for the event
   - Groups by `school_id`
   - Correlates with MySQL metrics

#### Test Case: Email → User → School
1. Find an email event in logs
2. Verify it has:
   - `event_type="email"`
   - `recipient_email` normalized
   - `mysql_join_user_email`
3. Verify the email matches a user in MySQL:
   ```sql
   SELECT u.id, u.email, u.schoolId, s.name
   FROM users u
   JOIN schools s ON u.schoolId = s.id
   WHERE u.email = '<recipient_email_from_log>';
   ```

## Common Issues and Fixes

### Issue: IDs are strings instead of integers

**Symptom:**
```json
{"user_id": "12345", "mysql_join_user_id": "12345"}
```

**Fix:** Check Vector transform - ensure `to_int()` is called:
```vrl
if .user_id {
  .user_id = to_int(.user_id) ?? null
}
```

### Issue: Usernames not normalized

**Symptom:**
```json
{"username": "John.Doe@example.com", "mysql_join_user_name": "John.Doe@example.com"}
```

**Fix:** Ensure username normalization in Vector:
```vrl
.username = downcase(.username)
.username_normalized = replace(.username, r'@.*$', "")
```

### Issue: Missing join hints

**Symptom:**
```json
{"user_id": 12345, "mysql_joins": null}
```

**Fix:** Ensure join hint generation runs after identifier extraction:
```vrl
.mysql_joins = []
if .mysql_join_user_id {
  .mysql_joins = append(.mysql_joins, "users.id")
}
```

### Issue: Email case mismatch

**Symptom:** Log email doesn't match MySQL email (case difference)

**Fix:** Ensure all emails are lowercased:
```vrl
if .email {
  .email = downcase(.email)
}
```

## Automated Validation Script

Create a validation script to run these checks:

```bash
#!/bin/bash
# validate-joins.sh

echo "Validating MOAD join compatibility..."

# Check structured logs exist
if [ ! -d "/data/moad/logs/structured" ]; then
    echo "❌ Structured logs directory not found"
    exit 1
fi

# Check join compatibility flag
JOIN_COMPATIBLE=$(find /data/moad/logs/structured -name "*.jsonl" -exec cat {} \; | jq 'select(.moad_join_compatible == true)' | jq -s 'length')
TOTAL_EVENTS=$(find /data/moad/logs/structured -name "*.jsonl" -exec cat {} \; | jq -s 'length')

if [ "$JOIN_COMPATIBLE" -lt $((TOTAL_EVENTS * 90 / 100)) ]; then
    echo "❌ Less than 90% of events are join-compatible"
    exit 1
fi

echo "✅ Join compatibility validation passed"
```

## Performance Validation

### Query Performance
- LogQL queries with join hints should complete in <5 seconds
- Grafana dashboards should load in <10 seconds
- Vector processing should not add >100ms latency per event

### Storage Efficiency
- Structured logs should be <2x size of raw logs (with compression)
- Loki retention should maintain 30-day window
- Prometheus metrics should be retained for 30 days

## Continuous Monitoring

Set up alerts for:
1. **Join compatibility rate**: Alert if <90% of events have join hints
2. **Identifier extraction failures**: Alert on extraction errors in Vector logs
3. **Type conversion errors**: Alert when `to_int()` returns null for expected IDs
4. **Missing required identifiers**: Alert when critical events lack join hints

## Conclusion

Regular validation ensures that the MOAD stack maintains join compatibility between logs and MySQL schema. This enables reliable analytics and root-cause analysis across the entire SchoolSoft platform.

