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

# Display Grafana credentials
echo "Grafana URL: ${GRAFANA_URL}"
echo "Grafana Username: admin"
echo "Grafana Password: admin (default - change after first login)"
echo ""
echo "Note: If Grafana was already initialized, the password may have been changed."
echo "      To reset: docker exec -it moad-grafana grafana cli admin reset-admin-password <new_password>"

