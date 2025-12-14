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

# Construct DATA_SOURCE_NAME at runtime (not at docker-compose parse time)
export DATA_SOURCE_NAME="${MYSQL_USER}:${MYSQL_PASSWORD}@tcp(${MYSQL_HOST}:3306)/"

# Debug output (can be removed in production)
echo "Starting mysqld_exporter with DATA_SOURCE_NAME for user: ${MYSQL_USER}@${MYSQL_HOST}" >&2

# Execute the original mysqld_exporter command
exec /bin/mysqld_exporter "$@"

