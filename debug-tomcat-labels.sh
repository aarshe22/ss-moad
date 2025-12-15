#!/bin/bash
# Debug script to check Tomcat log processing and labels

echo "=== Debugging Tomcat Log Processing ==="
echo ""

echo "1. Check if Vector is reading Tomcat files:"
docker logs moad-vector 2>&1 | grep -iE "tomcat|catalina|Found new file" | tail -10
echo ""

echo "2. Check for Tomcat parsing errors:"
docker logs moad-vector 2>&1 | grep -iE "error.*tomcat|failed.*tomcat|parse_tomcat.*error" | tail -20
echo ""

echo "3. Check actual Tomcat log format (first 5 lines):"
docker exec moad-vector head -5 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out 2>/dev/null || echo "Cannot read file"
echo ""

echo "4. Check timestamp format in logs:"
docker exec moad-vector head -10 /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out 2>/dev/null | grep -oE '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' | head -3 || echo "No matching timestamp format found"
echo ""

echo "5. Query Loki for ANY logs with 'tomcat' in the message:"
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\"} |= \"tomcat\"&limit=5&start=$(($(date +%s) - 86400))000000000&end=$(date +%s)000000000" 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); results=data.get('data', {}).get('result', []); print('Found', len(results), 'streams'); [print('  Stream:', stream.get('stream', {})) for stream in results[:3]]" 2>/dev/null || echo "Query failed"
echo ""

echo "6. Query Loki for logs with source_component field (JSON filter):"
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\"} | json | source_component=\"tomcat\"&limit=5&start=$(($(date +%s) - 86400))000000000&end=$(date +%s)000000000" 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); results=data.get('data', {}).get('result', []); print('Found', len(results), 'streams with source_component=tomcat')" 2>/dev/null || echo "Query failed"
echo ""

echo "7. Check Vector config for Tomcat source:"
grep -A 10 "tomcat_cm:" vector/vector.yml | head -12
echo ""

echo "8. Check what labels are being sent to Loki:"
grep -A 20 "loki_all:" vector/vector.yml | grep -A 10 "labels:"
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Next steps:"
echo "1. If no errors above, try querying Grafana with: {app=\"CM\"} |= \"Exception\""
echo "2. Check Label browser in Grafana to see available labels"
echo "3. Try JSON field filtering: {app=\"CM\"} | json | source_component=\"tomcat\""

