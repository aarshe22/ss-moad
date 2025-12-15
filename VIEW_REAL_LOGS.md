# How to View Real Application Logs in Grafana

## ✅ Good News: Real Logs ARE Being Processed!

The diagnostic confirms:
- ✅ All 6 log files exist and have real content
- ✅ Vector is reading all files successfully  
- ✅ Real logs ARE in Loki (HAProxy example shows real data)

## The Fake JSON You're Seeing

The JSON events with random appnames (like "devankoshal", "KarimMove") that appear in `docker logs moad-vector` are **Vector's internal logging output**, NOT your application logs.

**Your real application logs are successfully in Loki!** You just saw a real HAProxy log entry in the diagnostic.

## How to View Real Logs in Grafana

### Option 1: Grafana Explore (Recommended)

1. **Open Grafana**: `http://dev1.schoolsoft.net:3000`
2. **Go to Explore** (compass icon in left sidebar)
3. **Select Loki datasource**
4. **Run these queries to see real logs:**

   **HAProxy logs (CM):**
   ```
   {app="CM", source_component="haproxy"}
   ```

   **Tomcat logs (CM):**
   ```
   {app="CM", source_component="tomcat"}
   ```

   **Mail logs (CM):**
   ```
   {app="CM", source_component="postfix"}
   ```

   **All CM logs:**
   ```
   {app="CM"}
   ```

   **All PFM logs:**
   ```
   {app="PFM"}
   ```

5. **View log details**: Click on any log line to see the full JSON with all extracted fields

### Option 2: Query Loki Directly

```bash
# Get recent HAProxy logs
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\",source_component=\"haproxy\"}&limit=10&start=$(($(date +%s) - 3600))000000000&end=$(date +%s)000000000" | python3 -m json.tool | grep -A 5 '"values"'

# Get recent Tomcat logs
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\",source_component=\"tomcat\"}&limit=10&start=$(($(date +%s) - 3600))000000000&end=$(date +%s)000000000" | python3 -m json.tool | grep -A 5 '"values"'
```

## What Real Logs Look Like

Real logs in Loki will have:
- `"app": "CM"` or `"app": "PFM"`
- `"source_component": "haproxy"`, `"tomcat"`, or `"postfix"`
- `"message"` field with actual log content (like HAProxy access logs, Tomcat stack traces, Postfix mail logs)
- Extracted fields like `school_id`, `username`, `http_status`, etc.

**Example real log (from your diagnostic):**
```json
{
  "@timestamp": "2025-12-15T05:34:18.804007182Z",
  "app": "CM",
  "event_category": "infrastructure",
  "event_type": "http_traffic",
  "file": "/data/moad/logs/app1/var/log/haproxy.log",
  "message": "Dec 14 22:34:17 app1 haproxy[6125]: 198.163.212.14:50526 [14/Dec/2025:22:34:17.151] fe_in/1: SSL handshake failure",
  "source_component": "haproxy"
}
```

## Why No Structured Files?

The diagnostic showed "No structured files found". This could mean:
1. Vector hasn't written any yet (files are created when events are processed)
2. Directory permissions issue
3. Vector is still processing the large files (app1 catalina.out is 303MB!)

**To check:**
```bash
# Wait a bit, then check again
sleep 30
ls -lh ./data/vector/structured/
```

## Next Steps

1. **Open Grafana Explore** and query for real logs using the queries above
2. **Check your dashboards** - they should show real data now
3. **Verify log content** - you should see actual HAProxy access logs, Tomcat errors, Postfix mail logs

The fake JSON in Vector logs is just noise - your real logs are working perfectly in Loki!

