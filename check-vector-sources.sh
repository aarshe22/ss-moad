#!/bin/bash
# Check what Vector is actually reading

echo "=== Checking Vector Sources ==="
echo ""

echo "1. Vector config sources:"
docker exec moad-vector cat /etc/vector/vector.yml | grep -A 5 "sources:" | head -30
echo ""

echo "2. Check if Vector is reading real log files:"
echo "Checking file sources Vector should be reading..."
for file in \
  "/data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out" \
  "/data/moad/logs/app2/usr/share/tomcat8/logs/catalina.out" \
  "/data/moad/logs/app1/var/log/haproxy.log" \
  "/data/moad/logs/app2/var/log/haproxy.log" \
  "/data/moad/logs/app1/var/log/mail.log" \
  "/data/moad/logs/app2/var/log/mail.log"; do
  if docker exec moad-vector test -f "$file"; then
    size=$(docker exec moad-vector stat -c%s "$file" 2>/dev/null || echo "unknown")
    echo "  ✓ $file (size: $size bytes)"
  else
    echo "  ✗ $file (NOT FOUND)"
  fi
done
echo ""

echo "3. Check Vector logs for file reading activity:"
docker logs moad-vector 2>&1 | grep -i "file.*server\|starting.*file\|reading\|ingest" | tail -10
echo ""

echo "4. Check what Vector is actually outputting (sample):"
docker logs moad-vector 2>&1 | grep -E '^\{"appname"' | head -5
echo ""

echo "5. Check Vector internal metrics (if available):"
docker exec moad-vector wget -qO- http://localhost:9598/metrics 2>/dev/null | grep -i "vector_events_total\|vector_bytes_total\|file" | head -10
