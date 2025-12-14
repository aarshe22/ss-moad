#!/bin/sh
# Entrypoint script for mysqld-exporter
# Creates .my.cnf file in /tmp (writable by nobody user) from environment variables
# Container runs as 'nobody' user, so we can't write to /root/.my.cnf

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

# Create .my.cnf file in /tmp (writable by nobody user)
# mysqld-exporter will look for it in HOME, so we'll set HOME to /tmp
MY_CNF_FILE="/tmp/.my.cnf"

# Write .my.cnf file with MySQL credentials
cat > "$MY_CNF_FILE" <<EOF
[client]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
host=${MYSQL_HOST}
port=3306
EOF

# Set restrictive permissions on .my.cnf (only owner can read)
chmod 600 "$MY_CNF_FILE"

# Debug output (don't print password)
echo "Starting mysqld_exporter with MySQL connection: ${MYSQL_USER}@${MYSQL_HOST}:3306" >&2
echo "Created .my.cnf file at: $MY_CNF_FILE" >&2

# Execute mysqld_exporter with explicit config file path
# Use --config.my-cnf flag to specify the config file location
# Pass through any additional arguments from docker-compose command section
exec /bin/mysqld_exporter --config.my-cnf="$MY_CNF_FILE" "$@"

