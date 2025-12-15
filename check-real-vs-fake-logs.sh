#!/bin/bash
# Check if Vector is processing real logs or just fake test data

echo "=== Checking Real vs Fake Logs ==="
echo ""

echo "1. Sample of what Vector is outputting (from Vector logs):"
docker logs moad-vector 2>&1 | grep -E '^\{"appname"' | head -3
echo ""

echo "2. Check if real log files have content:"
echo "   app1 catalina.out (last 3 lines):"
docker exec moad-vector tail -3 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out 2>/dev/null | head -3
echo ""

echo "3. Check what's in Loki (query for CM app):"
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\"}&limit=2&start=$(($(date +%s) - 3600))000000000&end=$(date +%s)000000000" 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -A 5 '"values"' | head -10 || echo "Query failed or no data"
echo ""

echo "4. Check Vector structured files for real logs:"
if [ -d "./data/vector/structured" ] && [ -n "$(ls -A ./data/vector/structured/*.jsonl.gz 2>/dev/null)" ]; then
  latest=$(find ./data/vector/structured -name "*.jsonl.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
  echo "   Latest file: $latest"
  echo "   Sample entry:"
  zcat "$latest" 2>/dev/null | head -1 | python3 -m json.tool 2>/dev/null | head -15 || zcat "$latest" 2>/dev/null | head -1
else
  echo "   No structured files found"
fi
echo ""

echo "5. Check Vector file source status:"
docker logs moad-vector 2>&1 | grep -i "file.*server\|starting.*file" | tail -5
