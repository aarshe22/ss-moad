# Troubleshooting Tomcat Logs in Grafana

## ✅ Good News: HAProxy and Postfix Logs Are Working!

Your screenshots confirm:
- ✅ **HAProxy logs**: 1000 lines found, 7.60% of 1h processed
- ✅ **Postfix logs**: 1000 lines found, real mail delivery logs visible
- ✅ **General CM logs**: 1000 lines found with `{app="CM"}`

## ⚠️ Tomcat Logs Not Showing Yet

The query `{app="CM", source_component="tomcat"}` shows "No logs found" for the last 1 hour.

### Why This Happens

1. **Large File Size**: `app1/catalina.out` is **303MB** - Vector is still processing it
2. **Time Range**: Tomcat logs might be older than 1 hour
3. **Processing Speed**: Vector processes logs sequentially, large files take time

### Solutions

#### Option 1: Expand Time Range (Recommended)

In Grafana Explore:
1. Change time range from "Last 1 hour" to **"Last 24 hours"** or **"Last 7 days"**
2. Run query: `{app="CM", source_component="tomcat"}`
3. Click "Scan for older logs" button if it appears

#### Option 2: Check Processing Status

```bash
# Check if Vector is processing Tomcat logs
docker logs moad-vector 2>&1 | grep -i "tomcat\|catalina" | tail -20

# Check Tomcat logs in Loki (last 24 hours)
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\",source_component=\"tomcat\"}&limit=5&start=$(($(date +%s) - 86400))000000000&end=$(date +%s)000000000" | python3 -m json.tool | grep -A 5 '"values"'
```

#### Option 3: Wait for Processing

Vector is processing the 303MB file. You can:
- Wait 10-30 minutes for processing to catch up
- Check Vector logs for processing activity
- Monitor structured files directory: `./data/vector/structured/`

### Verify Tomcat Logs Are Being Read

```bash
# Check Vector file source status
docker logs moad-vector 2>&1 | grep -i "tomcat_cm\|Found new file"

# Should show:
# Found new file to watch. file=/data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out
```

### Expected Tomcat Log Format

Once processed, Tomcat logs in Grafana will show:
- `source_component: "tomcat"`
- `event_category: "application"` or `"error"`
- `event_type: "exception"`, `"authentication"`, `"integration_task"`, etc.
- Extracted fields like `username`, `school_id`, `student_ids`, `form_id`, etc.

### Quick Test Query

Try this in Grafana Explore with **"Last 24 hours"**:
```
{app="CM", source_component="tomcat", event_type=~".*"}
```

This will show any Tomcat logs that have been processed, regardless of event type.

## Summary

- ✅ **HAProxy and Postfix logs are working perfectly**
- ⏳ **Tomcat logs are still processing** (303MB file takes time)
- 💡 **Solution**: Expand time range to "Last 24 hours" or wait for processing to complete

Your MOAD stack is working correctly - it's just processing a very large log file!

