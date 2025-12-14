#!/bin/sh
# Entrypoint script for Grafana
# Sets GF_SECURITY_ADMIN_PASSWORD from GRAFANA_ADMIN_PASSWORD environment variable

# Read GRAFANA_ADMIN_PASSWORD from environment (loaded from .env via env_file)
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-admin}"

# Check if admin password is set (warn if using default)
if [ -z "$GRAFANA_PASS" ] || [ "$GRAFANA_PASS" = "admin" ]; then
    echo "Warning: Grafana admin password is not set or using default 'admin'" >&2
    echo "Please set GRAFANA_ADMIN_PASSWORD in .env file for security" >&2
fi

# Always set GF_SECURITY_ADMIN_PASSWORD for Grafana (must be set before Grafana starts)
# This overrides any value that might have been set in docker-compose.yml
export GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_PASS"

echo "Grafana starting with admin user: ${GF_SECURITY_ADMIN_USER:-admin}" >&2
if [ "$GRAFANA_PASS" != "admin" ]; then
    echo "Grafana admin password is set (from GRAFANA_ADMIN_PASSWORD)" >&2
else
    echo "Grafana admin password: using default 'admin' (set GRAFANA_ADMIN_PASSWORD in .env)" >&2
fi

# Validate provisioning directory exists
if [ ! -d "/etc/grafana/provisioning" ]; then
    echo "Warning: Grafana provisioning directory not found" >&2
    echo "Datasources and dashboards may not be auto-configured" >&2
fi

# Validate dashboards directory exists
if [ ! -d "/var/lib/grafana/dashboards" ]; then
    echo "Warning: Grafana dashboards directory not found" >&2
fi

echo "Grafana starting with admin user: ${GF_SECURITY_ADMIN_USER:-admin}" >&2

# Execute the original Grafana entrypoint
exec /run.sh "$@"

