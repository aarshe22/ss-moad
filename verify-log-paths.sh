#!/bin/bash
# Verify log paths match after docker-compose mount change

echo "=== Verifying Log Path Configuration ==="
echo ""

echo "Actual log file locations on HOST:"
echo "  Catalina: /data/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  Catalina: /data/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  HAProxy:  /data/logs/app1/var/log/haproxy.log"
echo "  HAProxy:  /data/logs/app2/var/log/haproxy.log"
echo "  Mail:     /data/logs/app1/var/log/mail.log"
echo "  Mail:     /data/logs/app2/var/log/mail.log"
echo ""

echo "Docker-compose mount: /data/logs:/data/moad/logs:ro"
echo ""

echo "Vector config expects (in CONTAINER):"
echo "  Catalina: /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  Catalina: /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  HAProxy:  /data/moad/logs/app1/var/log/haproxy.log"
echo "  HAProxy:  /data/moad/logs/app2/var/log/haproxy.log"
echo "  Mail:     /data/moad/logs/app1/var/log/mail.log"
echo "  Mail:     /data/moad/logs/app2/var/log/mail.log"
echo ""

echo "=== Path Mapping ==="
echo "Host /data/logs/app1/... → Container /data/moad/logs/app1/... ✓"
echo "Host /data/logs/app2/... → Container /data/moad/logs/app2/... ✓"
echo ""

echo "=== Verification ==="
echo "After restarting Vector, these commands should work:"
echo ""
echo "  docker exec moad-vector ls -la /data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  docker exec moad-vector ls -la /data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out"
echo "  docker exec moad-vector ls -la /data/moad/logs/app1/var/log/haproxy.log"
echo "  docker exec moad-vector ls -la /data/moad/logs/app2/var/log/haproxy.log"
echo "  docker exec moad-vector ls -la /data/moad/logs/app1/var/log/mail.log"
echo "  docker exec moad-vector ls -la /data/moad/logs/app2/var/log/mail.log"
