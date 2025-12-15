#!/bin/bash
# Find where real application logs are and what Vector is actually reading

echo "=== Finding Real Application Logs ==="
echo ""

echo "1. Check if Vector is reading real log files:"
echo "   Looking for file reading activity in Vector logs..."
docker logs moad-vector 2>&1 | grep -i "file.*server\|starting.*file\|file_source" | tail -10
echo ""

echo "2. Check actual log file content (sample from each):"
echo ""
echo "=== app1 catalina.out (first 5 lines) ==="
docker exec moad-vector head -5 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out 2>/dev/null || echo "File not accessible"
echo ""

echo "=== app2 catalina.out (first 5 lines) ==="
docker exec moad-vector head -5 /data/moad/logs/app2/usr/share/tomcat8/logs/catalina.out 2>&1 | head -5
echo ""

echo "=== app1 haproxy.log (first 5 lines) ==="
docker exec moad-vector head -5 /data/moad/logs/app1/var/log/haproxy.log 2>&1 | head -5
echo ""

echo "=== app1 mail.log (first 5 lines) ==="
docker exec moad-vector head -5 /data/moad/logs/app1/var/log/mail.log 2>&1 | head -5
echo ""

echo "3. Check what Vector is outputting to Loki (sample):"
echo "   Querying Loki for recent logs..."
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\"}&limit=3&start=$(($(date +%s) - 3600))000000000&end=$(date +%s)000000000" 2>/dev/null | jq -r '.data.result[0].values[0][1]' 2>/dev/null | head -1 | jq . 2>/dev/null || echo "No CM logs found or jq not available"
echo ""

echo "4. Check Vector structured files (real processed logs):"
if [ -d "./data/vector/structured" ]; then
  latest_file=$(find ./data/vector/structured -name "*.jsonl.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
  if [ -n "$latest_file" ]; then
    echo "   Latest structured file: $latest_file"
    echo "   Sample log entry:"
    zcat "$latest_file" 2>/dev/null | head -1 | jq . 2>/dev/null | head -20 || zcat "$latest_file" 2>/dev/null | head -1
  else
    echo "   No structured files found"
  fi
else
  echo "   Structured files directory not found"
fi
echo ""

echo "5. Check Vector metrics for file reading:"
docker exec moad-vector wget -qO- http://localhost:9598/metrics 2>/dev/null | grep -i "vector_events_total\|file.*read\|source.*events" | head -10
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "If you see real log content above, Vector should be processing it."
echo "If you only see fake JSON, check if Vector is actually reading the files."

