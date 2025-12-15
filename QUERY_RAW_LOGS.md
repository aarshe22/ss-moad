# How to Query Raw Logs and Filter by String in Grafana

## Query Raw Logs Without Labels

In Grafana Explore, you can query raw log content using LogQL's text search capabilities:

### Method 1: Search Entire Log Message

**Query raw logs and filter by string:**
```
{app="CM"} |= "Exception"
```

This searches for any log line containing "Exception" in the message field.

**More examples:**
```
# Search for specific error
{app="CM"} |= "NullPointerException"

# Search for username
{app="CM"} |= "john.doe"

# Search for school ID
{app="CM"} |= "schoolId: 123"

# Search for specific class/method
{app="CM"} |= "AbstractBean.baseInit"
```

### Method 2: Search Specific Fields

**Search in message field:**
```
{app="CM"} | json | message =~ ".*Exception.*"
```

**Search in any JSON field:**
```
{app="CM"} | json | username =~ ".*admin.*"
```

### Method 3: Multiple String Filters

**Combine multiple search terms:**
```
{app="CM"} |= "Exception" |= "AbstractBean"
```

**Exclude certain strings:**
```
{app="CM"} |= "Exception" != "INFO"
```

### Method 4: Case-Insensitive Search

```
{app="CM"} |~ "(?i)exception"
```

## Check if Tomcat Logs Are Being Processed

### Query 1: Check if ANY Tomcat logs exist (no label filter)
```
{app="CM"} | json | source_component="tomcat"
```

### Query 2: Search raw message for Tomcat patterns
```
{app="CM"} |= "com.schoolsoft" |= "AbstractBean"
```

### Query 3: Check for stack traces
```
{app="CM"} |= "at com.schoolsoft" |= "Exception"
```

### Query 4: Check all logs from Tomcat file path
```
{app="CM"} | json | file=~".*tomcat.*"
```

## Verify Labels Are Being Set

### Check what labels exist for CM logs:
1. In Grafana Explore, click **"Label browser"** button
2. Select `app="CM"`
3. See what other labels are available (should show `source_component`, `event_type`, `event_category`, `host`)

### Query with label that might be missing:
```
{app="CM", source_component="tomcat"}
```

If this returns nothing, try:
```
{app="CM"} | json | source_component="tomcat"
```

## Debug Tomcat Log Processing

### Check if Vector is reading Tomcat logs:
```bash
# Check Vector logs for Tomcat processing
docker logs moad-vector 2>&1 | grep -i "tomcat\|parse_tomcat" | tail -50

# Check for errors
docker logs moad-vector 2>&1 | grep -i "error.*tomcat\|failed.*tomcat" | tail -20

# Check if file is being watched
docker logs moad-vector 2>&1 | grep -i "Found new file.*tomcat\|catalina"
```

### Check actual log file format:
```bash
# View first few lines of Tomcat log
docker exec moad-vector head -20 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out

# Check timestamp format
docker exec moad-vector head -5 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out | grep -oE '^\d{4}-\d{2}-\d{2}'
```

## Common Issues

### Issue 1: Timestamp Format Mismatch

Vector expects: `YYYY-MM-DD HH:MM:SS`
If your logs use a different format, the timestamp parsing will fail.

**Solution:** Check actual log format and update Vector config if needed.

### Issue 2: Multiline Parsing Issues

Tomcat stack traces span multiple lines. Vector's multiline parser might not be capturing them correctly.

**Solution:** Try querying without `source_component` label:
```
{app="CM"} |= "at com.schoolsoft"
```

### Issue 3: Missing Labels

If `source_component` label isn't being set, logs won't show up with that filter.

**Solution:** Use JSON field filtering instead:
```
{app="CM"} | json | source_component="tomcat"
```

## Quick Test Queries

Try these in Grafana Explore (set time range to "Last 24 hours"):

1. **All CM logs (no filter):**
   ```
   {app="CM"}
   ```

2. **Search for exceptions:**
   ```
   {app="CM"} |= "Exception"
   ```

3. **Search for specific class:**
   ```
   {app="CM"} |= "AbstractBean"
   ```

4. **Check if source_component field exists:**
   ```
   {app="CM"} | json | source_component
   ```

5. **All logs with tomcat in file path:**
   ```
   {app="CM"} | json | file=~".*tomcat.*"
   ```

## Next Steps

1. **Try raw text search first** - `{app="CM"} |= "Exception"` to see if logs are there
2. **Check Label browser** - See what labels are actually available
3. **Use JSON field filtering** - `| json | source_component="tomcat"` if label isn't working
4. **Check Vector logs** - See if there are parsing errors

