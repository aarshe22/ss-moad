#!/bin/sh
# Entrypoint script for Loki
# Validates configuration file exists and is readable before starting

LOKI_CONFIG="/etc/loki/local-config.yaml"

# Validate config file exists
if [ ! -f "$LOKI_CONFIG" ]; then
    echo "Error: Loki configuration file not found: $LOKI_CONFIG" >&2
    echo "Please ensure loki/loki-config.yml is mounted correctly" >&2
    exit 1
fi

# Validate config file is readable
if [ ! -r "$LOKI_CONFIG" ]; then
    echo "Error: Loki configuration file is not readable: $LOKI_CONFIG" >&2
    echo "Please check file permissions" >&2
    exit 1
fi

# Validate data directory is writable
if [ -d "/loki" ] && [ ! -w "/loki" ]; then
    echo "Warning: Loki data directory /loki exists but is not writable" >&2
    echo "Loki may not be able to store data" >&2
fi

echo "Loki configuration validated, starting..." >&2

# Execute the original Loki command
exec /usr/bin/loki "$@"

