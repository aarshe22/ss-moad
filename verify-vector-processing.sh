#!/bin/bash
# Verify Vector is processing logs and sending to Loki

echo "=== Vector Processing Verification ==="
echo ""

echo "1. Checking Vector logs for file processing..."
docker logs moad-vector --tail 100 | grep -i -E "file|read|ingest|processing|events" | tail -20
echo ""

echo "2. Checking Vector logs for Loki sending..."
docker logs moad-vector --tail 100 | grep -i -E "loki|sending|push|http" | tail -10
echo ""

echo "3. Checking Vector for errors..."
docker logs moad-vector --tail 100 | grep -i error | tail -10
echo ""

echo "4. Testing Loki query (should return log lines)..."
echo "Query: {app=\"CM\"}"
docker exec moad-loki wget -qO- "http://localhost:3100/loki/api/v1/query_range?query={app=\"CM\"}&limit=5" 2>/dev/null | head -20
echo ""

echo "5. Checking Vector metrics (if available)..."
docker exec moad-vector wget -qO- http://localhost:9598/metrics 2>/dev/null | grep -i "vector_events\|vector_bytes" | head -10
echo ""

echo "=== Next Steps ==="
echo "1. Open Grafana: http://dev1.schoolsoft.net:3000"
echo "2. Go to Explore → Select Loki datasource"
echo "3. Run query: {app=\"CM\"}"
echo "4. You should see log lines appearing!"
echo ""

