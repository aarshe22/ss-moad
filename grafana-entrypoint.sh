#!/bin/sh
# Entrypoint script for Grafana
# Validates provisioning paths - password is handled by Grafana's default behavior

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
echo "Note: Grafana uses default password 'admin' on first launch. Change it after first login." >&2

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

