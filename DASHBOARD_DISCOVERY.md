# How to Discover MOAD Dashboards in Grafana

## Automatic Discovery

Grafana is configured to **automatically discover** all dashboards in the `grafana/dashboards/` directory. The provisioning configuration (`grafana/provisioning/dashboards/dashboards.yml`) tells Grafana to:

- Scan `/var/lib/grafana/dashboards` every 10 seconds
- Auto-import any `.json` dashboard files
- Place them in the **"MOAD / Executive"** folder

## Steps to Access Dashboards

### 1. Restart Grafana Container (Recommended)

After pulling new dashboards, restart Grafana to ensure it picks them up:

```bash
# Option 1: Use MOAD Manager
./moad-manager.sh
# Select: "8. Docker: Restart Individual Container"
# Choose: moad-grafana

# Option 2: Use docker compose directly
docker compose restart grafana
```

### 2. Wait for Auto-Provisioning

Grafana checks for new dashboards every **10 seconds** (configured in `dashboards.yml`). If you don't restart, dashboards should appear within 10-20 seconds.

### 3. Access Dashboards in Grafana UI

1. **Open Grafana**: `http://dev1.schoolsoft.net:3000` (or your Grafana URL)
2. **Login**: `admin` / `admin` (default, change after first login)
3. **Navigate to Dashboards**:
   - Click **"Dashboards"** in the left sidebar
   - Click **"Browse"** or **"Dashboards"**
   - Look for folder: **"MOAD / Executive"**
   - All 13 dashboards should be listed there

### 4. Verify Dashboard Discovery

Check if dashboards are being discovered:

```bash
# Check Grafana logs for provisioning messages
docker logs moad-grafana | grep -i "dashboard\|provisioning"

# Verify dashboards are mounted in container
docker exec moad-grafana ls -la /var/lib/grafana/dashboards/

# Count dashboards in container
docker exec moad-grafana ls -1 /var/lib/grafana/dashboards/*.json | wc -l
```

## Dashboard List

You should see **13 dashboards** in the "MOAD / Executive" folder:

1. **Global Platform Overview** - Executive-level platform health
2. **Conference Manager (CM)** - CM application metrics
3. **Parent / Family Manager (PFM)** - PFM application metrics
4. **HAProxy** - Traffic & load balancing
5. **Postfix** - Mail flow & delivery
6. **Authentication Correlation** - Cross-service auth analysis
7. **School-Centric Error Analysis** - Drill-down by school
8. **User / Student Error Analysis** - Drill-down by user
9. **Top Errors & Offenders** - Error aggregation
10. **MySQL Performance** - Database health (existing)
11. **PermissionMan Analytics** - Form analytics (existing)
12. **Correlation Dashboard** - Cross-layer correlation (existing)
13. **Authentication Failures** - Security monitoring (existing)

## Troubleshooting

### Dashboards Not Appearing

1. **Check container is running**:
   ```bash
   docker ps | grep grafana
   ```

2. **Check provisioning config**:
   ```bash
   docker exec moad-grafana cat /etc/grafana/provisioning/dashboards/dashboards.yml
   ```

3. **Check dashboard files are mounted**:
   ```bash
   docker exec moad-grafana ls -la /var/lib/grafana/dashboards/
   ```

4. **Check Grafana logs for errors**:
   ```bash
   docker logs moad-grafana --tail 100 | grep -i error
   ```

5. **Manually trigger provisioning** (restart Grafana):
   ```bash
   docker compose restart grafana
   ```

### Dashboard JSON Errors

If a dashboard has JSON syntax errors, Grafana will skip it. Check logs:

```bash
docker logs moad-grafana | grep -i "dashboard.*error\|parse.*error"
```

### Folder Not Appearing

The folder name is set in `dashboards.yml`:
- Current: `"MOAD / Executive"`
- If it doesn't appear, check Grafana logs for provisioning errors

## Manual Import (If Needed)

If auto-provisioning doesn't work, you can manually import:

1. In Grafana UI: **"+" → "Import"**
2. Click **"Upload JSON file"**
3. Select dashboard JSON from `grafana/dashboards/`
4. Click **"Load"** and **"Import"**

## Verification Commands

```bash
# Count dashboards on host
ls -1 grafana/dashboards/*.json | wc -l
# Should show: 13

# Count dashboards in container
docker exec moad-grafana ls -1 /var/lib/grafana/dashboards/*.json | wc -l
# Should show: 13

# List all dashboard files
docker exec moad-grafana ls -1 /var/lib/grafana/dashboards/
```

## Next Steps

Once dashboards are visible:

1. **Start with Global Platform Overview** - Get overall health
2. **Explore service-specific dashboards** - CM, PFM, HAProxy, Postfix
3. **Use drill-down dashboards** - School-Centric, User-Centric
4. **Check correlation dashboards** - Authentication Correlation, Correlation Dashboard
5. **Review README**: See `grafana/dashboards/DASHBOARDS_README.md` for detailed usage

