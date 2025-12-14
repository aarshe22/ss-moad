#!/bin/bash
# show-grafana-url.sh - Display Grafana URL and password for easy copy/paste
# Can be run from shell at any time to get Grafana credentials

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Default Grafana URL
GRAFANA_URL="${GRAFANA_URL:-http://dev1.schoolsoft.net:3000}"

# Function to read value from .env file
read_env_value() {
    local key="$1"
    if [ -f .env ]; then
        grep "^${key}=" .env 2>/dev/null | cut -d'=' -f2- | sed 's/^["'\'']//;s/["'\'']$//'
    fi
}

# Read Grafana password from .env
GRAFANA_PASSWORD=$(read_env_value "GRAFANA_ADMIN_PASSWORD")

# Display Grafana credentials
echo "Grafana URL: ${GRAFANA_URL}"
echo "Grafana Username: admin"
if [ -n "$GRAFANA_PASSWORD" ]; then
    echo "Grafana Password: ${GRAFANA_PASSWORD}"
else
    echo "Grafana Password: (not set in .env file)"
fi

