#!/bin/sh
# Entrypoint script for mysqld-exporter
# Constructs DATA_SOURCE_NAME from individual environment variables at runtime
# This avoids docker-compose variable substitution issues and file permission problems

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

# Construct DATA_SOURCE_NAME in the format: user:password@(host:port)/
# The parentheses around host:port are required for proper parsing
DATA_SOURCE_NAME="${MYSQL_USER}:${MYSQL_PASSWORD}@(${MYSQL_HOST}:3306)/"

# Export DATA_SOURCE_NAME so mysqld_exporter can read it
export DATA_SOURCE_NAME

# Debug output (don't print password)
echo "Starting mysqld_exporter with MySQL connection: ${MYSQL_USER}@${MYSQL_HOST}:3306" >&2
echo "Using DATA_SOURCE_NAME environment variable" >&2

# Execute mysqld_exporter (it will read DATA_SOURCE_NAME automatically)
# Pass through any additional arguments from docker-compose command section
exec /bin/mysqld_exporter "$@"

