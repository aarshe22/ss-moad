#!/bin/sh
# Entrypoint script for Prometheus
# Validates configuration file exists and is readable before starting

PROMETHEUS_CONFIG="/etc/prometheus/prometheus.yml"

# Validate config file exists
if [ ! -f "$PROMETHEUS_CONFIG" ]; then
    echo "Error: Prometheus configuration file not found: $PROMETHEUS_CONFIG" >&2
    echo "Please ensure prometheus/prometheus.yml is mounted correctly" >&2
    exit 1
fi

# Validate config file is readable
if [ ! -r "$PROMETHEUS_CONFIG" ]; then
    echo "Error: Prometheus configuration file is not readable: $PROMETHEUS_CONFIG" >&2
    echo "Please check file permissions" >&2
    exit 1
fi

# Validate data directory is writable
if [ -d "/prometheus" ] && [ ! -w "/prometheus" ]; then
    echo "Warning: Prometheus data directory /prometheus exists but is not writable" >&2
    echo "Prometheus may not be able to store metrics" >&2
fi

echo "Prometheus configuration validated, starting..." >&2

# Execute the original Prometheus command with all arguments
exec /bin/prometheus "$@"

