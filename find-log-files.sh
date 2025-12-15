#!/bin/bash
# Find actual log file locations

echo "=== Searching for log files ==="
echo ""

echo "1. Searching entire /data directory..."
find /data -type f \( -name "catalina.out" -o -name "haproxy.log" -o -name "mail.log" \) 2>/dev/null | head -20
echo ""

echo "2. Checking common log locations..."
for path in \
  "/var/log/tomcat*/catalina.out" \
  "/var/log/haproxy.log" \
  "/var/log/mail.log" \
  "/opt/tomcat*/logs/catalina.out" \
  "/usr/local/tomcat*/logs/catalina.out" \
  "/home/*/tomcat*/logs/catalina.out"; do
  if ls $path 2>/dev/null | head -1; then
    echo "Found: $path"
  fi
done
echo ""

echo "3. Checking if /data/logs exists (different path)..."
if [ -d "/data/logs" ]; then
  echo "/data/logs exists:"
  find /data/logs -type f -name "*.log" -o -name "catalina.out" 2>/dev/null | head -10
else
  echo "/data/logs does not exist"
fi
echo ""

echo "4. Checking mount points..."
mount | grep -E "/data|log" | head -10
echo ""

echo "5. Checking fstab for NFS entries..."
grep -i nfs /etc/fstab 2>/dev/null || echo "No NFS entries in fstab"
