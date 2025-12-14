#!/bin/bash
# Inspection script for MySQL Exporter container
# Run these commands to help diagnose the configuration

echo "=== 1. Check environment variables ==="
docker exec moad-mysqld-exporter env | grep -E "(MYSQL|DATA_SOURCE)"

echo ""
echo "=== 2. Check if mysqld_exporter binary exists and get help ==="
docker exec moad-mysqld-exporter /bin/mysqld_exporter --help 2>&1 | head -50

echo ""
echo "=== 3. Check what user the container runs as ==="
docker exec moad-mysqld-exporter whoami
docker exec moad-mysqld-exporter id

echo ""
echo "=== 4. Check home directory and if .my.cnf can be created ==="
docker exec moad-mysqld-exporter sh -c 'echo "HOME=$HOME" && echo "PWD=$PWD" && ls -la ~ 2>&1 || echo "~ directory check failed"'

echo ""
echo "=== 5. Try to create .my.cnf in different locations ==="
docker exec moad-mysqld-exporter sh -c 'echo "[client]" > /tmp/.my.cnf.test && echo "user=test" >> /tmp/.my.cnf.test && cat /tmp/.my.cnf.test && rm /tmp/.my.cnf.test && echo "Success: Can write to /tmp"'
docker exec moad-mysqld-exporter sh -c 'echo "[client]" > ~/.my.cnf.test 2>&1 && cat ~/.my.cnf.test 2>&1 && rm ~/.my.cnf.test 2>&1 || echo "Failed to write to ~/.my.cnf"'

echo ""
echo "=== 6. Check if DATA_SOURCE_NAME format is correct ==="
echo "Current DATA_SOURCE_NAME (if set):"
docker exec moad-mysqld-exporter sh -c 'echo "$DATA_SOURCE_NAME"'

echo ""
echo "=== 7. Try running mysqld_exporter with DATA_SOURCE_NAME manually ==="
echo "This will show what format it expects:"
docker exec moad-mysqld-exporter sh -c 'export DATA_SOURCE_NAME="moad_ro:testpass@(10.0.0.13:3306)/" && /bin/mysqld_exporter --help 2>&1 | grep -A 5 -i "data.source\|connection" || echo "No DATA_SOURCE_NAME help found"'

echo ""
echo "=== 8. Check container filesystem structure ==="
docker exec moad-mysqld-exporter sh -c 'ls -la / && echo "---" && ls -la /bin/ | grep mysqld'

