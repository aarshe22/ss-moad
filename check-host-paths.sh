#!/bin/bash
# Check if log files exist on the host

echo "=== Checking log files on HOST ==="
echo ""

for path in \
  "/data/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out" \
  "/data/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out" \
  "/data/logs/app1/var/log/haproxy.log" \
  "/data/logs/app2/var/log/haproxy.log" \
  "/data/logs/app1/var/log/mail.log" \
  "/data/logs/app2/var/log/mail.log"; do
  if [ -f "$path" ]; then
    echo "✓ EXISTS: $path ($(ls -lh "$path" | awk '{print $5}'))"
  else
    echo "✗ MISSING: $path"
  fi
done

echo ""
echo "=== Checking directory structure ==="
echo ""

for dir in \
  "/data/logs/app1" \
  "/data/logs/app2" \
  "/data/logs/app1/usr" \
  "/data/logs/app2/usr" \
  "/data/logs/app1/var" \
  "/data/logs/app2/var"; do
  if [ -d "$dir" ]; then
    echo "✓ DIR: $dir"
  else
    echo "✗ MISSING DIR: $dir"
  fi
done
