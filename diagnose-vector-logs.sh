#!/bin/bash
# diagnose-vector-logs.sh - Diagnose Vector log file and Loki connectivity issues

echo "=== MOAD Vector & Loki Diagnostic ==="
echo ""

echo "1. Checking Vector container status..."
docker ps | grep vector
echo ""

echo "2. Checking what log files exist on host..."
echo "Searching /data/moad/logs for log files..."
find /data/moad/logs -type f \( -name "*.log" -o -name "catalina.out" \) 2>/dev/null | head -20
echo ""

echo "3. Checking directory structure..."
ls -la /data/moad/logs/ 2>/dev/null || echo "ERROR: /data/moad/logs does not exist or is not accessible"
echo ""

echo "4. Checking NFS mounts..."
mount | grep -i nfs | grep -i moad || echo "No NFS mounts found for /data/moad"
df -h | grep -i moad || echo "No /data/moad in df output"
echo ""

echo "5. Checking what Vector container can see..."
echo "Files visible to Vector container:"
docker exec moad-vector find /data/moad/logs -type f 2>/dev/null | head -20 || echo "ERROR: Vector cannot access /data/moad/logs"
echo ""

echo "6. Checking Vector logs for file-related errors..."
docker logs moad-vector 2>&1 | grep -i -E "file|read|error|not found|cannot" | tail -10
echo ""

echo "7. Checking Loki health..."
docker logs moad-loki --tail 20 | grep -i -E "error|503|unavailable|ready" | tail -5
echo ""

echo "8. Testing Loki connectivity from Vector..."
docker exec moad-vector wget -qO- http://loki:3100/ready 2>&1
echo ""

echo "9. Testing Loki readiness directly..."
docker exec moad-loki wget -qO- http://localhost:3100/ready 2>&1
echo ""

echo "10. Checking Vector config paths..."
echo "Expected paths in Vector config:"
docker exec moad-vector cat /etc/vector/vector.yml | grep -E "include:|/data/moad" | head -10
echo ""

echo "=== Diagnostic Complete ==="
echo ""
echo "Next steps:"
echo "1. If log files don't exist, check NFS mounts and actual log file locations"
echo "2. If paths are different, update vector/vector.yml with correct paths"
echo "3. If Loki healthcheck fails, check Loki logs and restart if needed"

