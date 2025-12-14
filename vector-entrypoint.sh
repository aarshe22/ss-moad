#!/bin/sh
# Entrypoint script for Vector
# Validates configuration file exists and is readable before starting

VECTOR_CONFIG="/etc/vector/vector.yml"

# Validate config file exists
if [ ! -f "$VECTOR_CONFIG" ]; then
    echo "Error: Vector configuration file not found: $VECTOR_CONFIG" >&2
    echo "Please ensure vector/vector.yml is mounted correctly" >&2
    exit 1
fi

# Validate config file is readable
if [ ! -r "$VECTOR_CONFIG" ]; then
    echo "Error: Vector configuration file is not readable: $VECTOR_CONFIG" >&2
    echo "Please check file permissions" >&2
    exit 1
fi

# Validate log directory is accessible (if mounted)
if [ -d "/data/moad/logs" ] && [ ! -r "/data/moad/logs" ]; then
    echo "Warning: Log directory /data/moad/logs exists but is not readable" >&2
    echo "Vector may not be able to process logs" >&2
fi

echo "Vector configuration validated, starting..." >&2

# Execute the original vector command
exec /usr/local/bin/vector "$@"

