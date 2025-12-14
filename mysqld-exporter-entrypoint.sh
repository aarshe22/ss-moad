#!/bin/sh
# Entrypoint script for mysqld-exporter
# Constructs DATA_SOURCE_NAME from individual environment variables at runtime
# This avoids docker-compose variable substitution issues

# Read individual MySQL connection variables from environment
# These are loaded from .env file via env_file directive
MYSQL_USER="${MYSQL_MOAD_RO_USER:-moad_ro}"
MYSQL_PASSWORD="${MYSQL_MOAD_RO_PASSWORD:-}"
MYSQL_HOST="${MYSQL_HOST:-}"

# Validate required variables
if [ -z "$MYSQL_PASSWORD" ]; then
    echo "Error: MYSQL_MOAD_RO_PASSWORD environment variable is not set" >&2
    echo "Please ensure .env file exists and contains MYSQL_MOAD_RO_PASSWORD" >&2
    exit 1
fi

if [ -z "$MYSQL_HOST" ]; then
    echo "Error: MYSQL_HOST environment variable is not set" >&2
    echo "Please ensure .env file exists and contains MYSQL_HOST" >&2
    exit 1
fi

# Use command-line flags instead of DATA_SOURCE_NAME (more reliable in v0.15.1)
# Format: --mysqld.address=host:port --mysqld.username=user --mysqld.password=password

# Debug output
echo "Starting mysqld_exporter with MySQL connection: ${MYSQL_USER}@${MYSQL_HOST}:3306" >&2

# Execute mysqld_exporter with command-line flags
# Pass through any additional arguments from docker-compose command section
exec /bin/mysqld_exporter \
    --mysqld.address="${MYSQL_HOST}:3306" \
    --mysqld.username="${MYSQL_USER}" \
    --mysqld.password="${MYSQL_PASSWORD}" \
    "$@"

