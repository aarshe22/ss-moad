#!/bin/bash
# moad-manager.sh - Comprehensive MOAD stack management interface
# Provides dialog-based interface for all MOAD operations

# Don't exit on error - return to main menu instead
set +e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Service URLs (configurable)
GRAFANA_URL="${GRAFANA_URL:-http://dev1.schoolsoft.net:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://dev1.schoolsoft.net:9090}"
LOKI_URL="${LOKI_URL:-http://dev1.schoolsoft.net:3100}"

# Lock file for single instance
LOCK_FILE="${LOCK_FILE:-/tmp/moad-manager.lock}"
LOCK_PID_FILE="${LOCK_PID_FILE:-/tmp/moad-manager.pid}"

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================

# Function to check and acquire lock
acquire_lock() {
    # Check if lock file exists
    if [ -f "$LOCK_FILE" ]; then
        # Check if the process is still running
        if [ -f "$LOCK_PID_FILE" ]; then
            local lock_pid
            lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null)
            if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
                # Process is still running
                echo -e "${RED}Error: MOAD Manager is already running (PID: $lock_pid)${NC}"
                echo -e "${YELLOW}If you believe this is a stale lock, you can remove it manually:${NC}"
                echo -e "  rm -f $LOCK_FILE $LOCK_PID_FILE"
                exit 1
            else
                # Stale lock - process is not running
                echo -e "${YELLOW}Warning: Found stale lock file. Cleaning up...${NC}"
                rm -f "$LOCK_FILE" "$LOCK_PID_FILE"
            fi
        else
            # Lock file exists but no PID file - stale lock
            echo -e "${YELLOW}Warning: Found stale lock file. Cleaning up...${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Create lock file
    touch "$LOCK_FILE" 2>/dev/null || {
        echo -e "${RED}Error: Cannot create lock file: $LOCK_FILE${NC}"
        exit 1
    }
    
    # Write PID to lock file
    echo $$ > "$LOCK_PID_FILE" 2>/dev/null || {
        echo -e "${RED}Error: Cannot create PID file: $LOCK_PID_FILE${NC}"
        rm -f "$LOCK_FILE"
        exit 1
    }
}

# Function to release lock on exit
release_lock() {
    rm -f "$LOCK_FILE" "$LOCK_PID_FILE"
}

# Trap to ensure lock is released on exit
# Function to cleanup on exit (used by trap)
cleanup_on_exit() {
    release_lock
    clear
    exit 0
}

# Trap to ensure lock is released on exit
trap 'cleanup_on_exit' INT TERM EXIT

# Acquire lock at startup
acquire_lock

# Function to check and install required package
check_and_install_package() {
    local package=$1
    local required=$2  # "required" or "optional"
    
    if command -v "$package" >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "${YELLOW}Note: '$package' not found.${NC}"
    if [ "$required" = "required" ]; then
        echo -e "${BLUE}This script requires $package.${NC}"
    else
        echo -e "${BLUE}Some features require $package.${NC}"
    fi
    echo ""
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${GREEN}sudo apt-get install -y $package${NC}"
        read -p "Install $package now? (yes/no) [no]: " install_pkg
        install_pkg=${install_pkg:-no}
        
        if [ "$install_pkg" = "yes" ]; then
            echo "Installing $package..."
            if sudo apt-get install -y "$package" >/dev/null 2>&1; then
                echo -e "${GREEN}$package installed successfully!${NC}"
                echo ""
                return 0
            else
                echo -e "${RED}Failed to install $package.${NC}"
                if [ "$required" = "required" ]; then
                    echo "Exiting."
                    exit 1
                fi
                return 1
            fi
        else
            if [ "$required" = "required" ]; then
                echo "$package is required for this script. Exiting."
                exit 1
            fi
            return 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        echo -e "  ${GREEN}sudo yum install -y $package${NC}"
        read -p "Install $package now? (yes/no) [no]: " install_pkg
        install_pkg=${install_pkg:-no}
        
        if [ "$install_pkg" = "yes" ]; then
            echo "Installing $package..."
            if sudo yum install -y "$package" >/dev/null 2>&1; then
                echo -e "${GREEN}$package installed successfully!${NC}"
                echo ""
                return 0
            else
                echo -e "${RED}Failed to install $package.${NC}"
                if [ "$required" = "required" ]; then
                    echo "Exiting."
                    exit 1
                fi
                return 1
            fi
        else
            if [ "$required" = "required" ]; then
                echo "$package is required for this script. Exiting."
                exit 1
            fi
            return 1
        fi
    else
        echo -e "${RED}Could not detect package manager. Please install $package manually.${NC}"
        if [ "$required" = "required" ]; then
            exit 1
        fi
        return 1
    fi
}

# Check if dialog is installed (required)
USE_DIALOG=false
if check_and_install_package "dialog" "required"; then
    USE_DIALOG=true
fi

# Check if jq is installed (required for backup/restore)
HAS_JQ=false
if check_and_install_package "jq" "required"; then
    HAS_JQ=true
fi

# Check if docker compose is available
if ! command -v docker >/dev/null 2>&1; then
    dialog --stdout --msgbox "Error: Docker is not installed or not in PATH." 8 50 2>&1 >/dev/null
    exit 1
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Error log file
ERROR_LOG="${ERROR_LOG:-moad-manager-errors.log}"

# Function to log errors
log_error() {
    local operation=$1
    local error_msg=$2
    local container=${3:-""}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ -n "$container" ]; then
        echo "[$timestamp] [CONTAINER:$container] [OPERATION:$operation] $error_msg" >> "$ERROR_LOG"
    else
        echo "[$timestamp] [OPERATION:$operation] $error_msg" >> "$ERROR_LOG"
    fi
}

# Function to log command errors (captures stderr and exit codes)
log_command_error() {
    local operation=$1
    local command=$2
    local container=${3:-""}
    local exit_code=$4
    local stderr_output=${5:-""}
    
    if [ $exit_code -ne 0 ]; then
        local error_msg="Command failed (exit code: $exit_code): $command"
        if [ -n "$stderr_output" ]; then
            error_msg="$error_msg | Error: $stderr_output"
        fi
        log_error "$operation" "$error_msg" "$container"
    fi
}

# Function to generate random password (14 characters: uppercase, lowercase, numbers)
generate_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 14
}

# Function to read value from .env file
read_env_value() {
    local key=$1
    if [ -f .env ]; then
        grep "^${key}=" .env 2>/dev/null | cut -d '=' -f2- | sed 's/^"//;s/"$//' || echo ""
    else
        echo ""
    fi
}

# Function to get MOAD containers (always fresh from docker)
get_moad_containers() {
    local containers
    local stderr_output
    stderr_output=$(docker compose ps --format "{{.Name}}" 2>&1 >/dev/null)
    containers=$(docker compose ps --format "{{.Name}}" 2>/dev/null | grep "^moad-" || echo "")
    
    if [ -n "$stderr_output" ] && echo "$stderr_output" | grep -qi "error\|failed"; then
        log_error "get_moad_containers" "$stderr_output"
    fi
    
    echo "$containers"
}

# Function to get all containers (running and stopped) - always fresh
get_all_containers() {
    local containers
    local stderr_output
    stderr_output=$(docker compose ps -a --format "{{.Name}}" 2>&1 >/dev/null)
    containers=$(docker compose ps -a --format "{{.Name}}" 2>/dev/null || echo "")
    
    if [ -n "$stderr_output" ] && echo "$stderr_output" | grep -qi "error\|failed"; then
        log_error "get_all_containers" "$stderr_output"
    fi
    
    echo "$containers"
}

# Function to get running containers - always fresh
get_running_containers() {
    local containers
    local stderr_output
    stderr_output=$(docker compose ps --format "{{.Name}}" --filter "status=running" 2>&1 >/dev/null)
    containers=$(docker compose ps --format "{{.Name}}" --filter "status=running" 2>/dev/null || echo "")
    
    if [ -n "$stderr_output" ] && echo "$stderr_output" | grep -qi "error\|failed"; then
        log_error "get_running_containers" "$stderr_output"
    fi
    
    echo "$containers"
}

# Function to get stopped containers - always fresh
get_stopped_containers() {
    local containers
    local stderr_output
    stderr_output=$(docker compose ps --format "{{.Name}}" --filter "status=stopped" 2>&1 >/dev/null)
    containers=$(docker compose ps --format "{{.Name}}" --filter "status=stopped" 2>/dev/null || echo "")
    
    if [ -n "$stderr_output" ] && echo "$stderr_output" | grep -qi "error\|failed"; then
        log_error "get_stopped_containers" "$stderr_output"
    fi
    
    echo "$containers"
}

# Function to get container status from docker (always fresh)
get_container_status_from_docker() {
    local container=$1
    local status
    local stderr_output
    
    # Check if container exists first (more efficient)
    if ! docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
        echo "not_found"
        return
    fi
    
    # Get status
    stderr_output=$(docker inspect --format='{{.State.Status}}' "$container" 2>&1 >/dev/null)
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    
    if [ -n "$stderr_output" ] && echo "$stderr_output" | grep -qi "error\|failed"; then
        log_error "get_container_status_from_docker" "$stderr_output" "$container"
    fi
    
    # Return "unknown" if status is empty or null
    if [ -z "$status" ] || [ "$status" = "null" ]; then
        echo "unknown"
    else
        echo "$status"
    fi
}

# ============================================================================
# ENVIRONMENT FILE MANAGEMENT
# ============================================================================

generate_env_file() {
    local existing_mysql_host=""
    local existing_mysql_user=""
    local existing_mysql_password=""
    local existing_grafana_admin_password=""
    local existing_mysql_grafana_password=""
    
    if [ -f .env ]; then
        dialog --stdout --yesno "WARNING: .env file already exists!\n\nDo you want to update it?" 8 50 2>&1 >/dev/null
        
        # Handle cancel/ESC - return to main menu
        if [ $? -ne 0 ]; then
            return
        fi
        
        # Load existing values
        existing_mysql_host=$(read_env_value "MYSQL_HOST")
        existing_mysql_user=$(read_env_value "MYSQL_MOAD_RO_USER")
        existing_mysql_password=$(read_env_value "MYSQL_MOAD_RO_PASSWORD")
        existing_grafana_admin_password=$(read_env_value "GRAFANA_ADMIN_PASSWORD")
        existing_mysql_grafana_password=$(read_env_value "MYSQL_GRAFANA_PASSWORD")
    fi
    
    # MySQL Host
    local mysql_host
    local exit_code
    if [ -n "$existing_mysql_host" ]; then
        mysql_host=$(dialog --stdout --inputbox "MySQL Host (IP address or hostname):" 10 60 "$existing_mysql_host" 2>&1)
        exit_code=$?
    else
        mysql_host=$(dialog --stdout --inputbox "MySQL Host (IP address or hostname):" 10 60 2>&1)
        exit_code=$?
    fi
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$mysql_host" ]; then
        return
    fi
    
    # MySQL User
    local mysql_user
    mysql_user=$(dialog --stdout --inputbox "MySQL User:" 10 60 "${existing_mysql_user:-moad_ro}" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ]; then
        return
    fi
    mysql_user=${mysql_user:-moad_ro}
    
    # MySQL Password
    local mysql_password
    if [ -n "$existing_mysql_password" ]; then
        dialog --stdout --yesno "Keep existing MySQL password?" 8 50 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            mysql_password="$existing_mysql_password"
        else
            mysql_password=$(dialog --stdout --inputbox "Enter new MySQL password:" 10 60 2>&1)
            exit_code=$?
            # Handle cancel/ESC - return to main menu
            if [ $exit_code -ne 0 ]; then
                return
            fi
        fi
    else
        mysql_password=$(dialog --stdout --inputbox "MySQL Password:" 10 60 2>&1)
        exit_code=$?
        # Handle cancel/ESC - return to main menu
        if [ $exit_code -ne 0 ] || [ -z "$mysql_password" ]; then
            return
        fi
    fi
    
    # Generate or preserve passwords
    local grafana_admin_password
    local mysql_grafana_password
    
    if [ -n "$existing_grafana_admin_password" ] || [ -n "$existing_mysql_grafana_password" ]; then
        dialog --stdout --yesno "Regenerate Grafana and MySQL Grafana passwords?" 8 50 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            dialog --stdout --infobox "Generating new secure random passwords..." 5 50 2>&1 >/dev/null
            sleep 1
            grafana_admin_password=$(generate_password)
            mysql_grafana_password=$(generate_password)
        else
            grafana_admin_password=${existing_grafana_admin_password:-$(generate_password)}
            mysql_grafana_password=${existing_mysql_grafana_password:-$(generate_password)}
        fi
    else
        dialog --stdout --infobox "Generating secure random passwords..." 5 50 2>&1 >/dev/null
        sleep 1
        grafana_admin_password=$(generate_password)
        mysql_grafana_password=$(generate_password)
    fi
    
    # Create .env file
    cat > .env << EOF
# MOAD Environment Variables
# Generated by moad-manager.sh on $(date)

# Grafana admin password (randomly generated)
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}

# MySQL server host (IP address recommended for Docker networks)
MYSQL_HOST=${mysql_host}

# MySQL exporter user (read-only access)
MYSQL_MOAD_RO_USER=${mysql_user}

# MySQL exporter password
MYSQL_MOAD_RO_PASSWORD=${mysql_password}

# MySQL Grafana readonly user password (randomly generated)
# Note: Per non-goals, direct MySQL queries from Grafana are discouraged
MYSQL_GRAFANA_PASSWORD=${mysql_grafana_password}
EOF
    
    local success_msg=".env file created successfully!\n\n"
    success_msg+="Generated passwords (save these securely):\n"
    success_msg+="  GRAFANA_ADMIN_PASSWORD: ${grafana_admin_password}\n"
    success_msg+="  MYSQL_GRAFANA_PASSWORD: ${mysql_grafana_password}\n\n"
    success_msg+="MySQL Configuration:\n"
    success_msg+="  MYSQL_HOST: ${mysql_host}\n"
    success_msg+="  MYSQL_MOAD_RO_USER: ${mysql_user}\n\n"
    success_msg+="Next steps:\n"
    success_msg+="  1. Review the .env file: cat .env\n"
    success_msg+="  2. Start MOAD stack: docker compose up -d\n"
    success_msg+="  3. Access Grafana: ${GRAFANA_URL}\n"
    success_msg+="     Username: admin\n"
    success_msg+="     Password: ${grafana_admin_password}"
    
    dialog --stdout --msgbox "$success_msg" 18 70 2>&1 >/dev/null
}

view_env_file() {
    if [ ! -f .env ]; then
        dialog --stdout --msgbox ".env file not found. Use 'Generate .env File' option first." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Use temporary file for dialog textbox (cannot use process substitution)
    local temp_file
    temp_file=$(mktemp /tmp/moad-env-XXXXXX)
    cat .env > "$temp_file"
    
    dialog --stdout --title ".env File Contents" --textbox "$temp_file" 20 70 2>&1 >/dev/null
    rm -f "$temp_file"
}

# ============================================================================
# DOCKER OPERATIONS
# ============================================================================

show_container_status() {
    local status_output
    status_output=$(docker compose ps 2>/dev/null || echo "No containers found or docker compose not available")
    
    # Use temporary file for dialog textbox (cannot use process substitution)
    local temp_file
    temp_file=$(mktemp /tmp/moad-status-XXXXXX)
    echo "$status_output" > "$temp_file"
    
    dialog --stdout --title "MOAD Container Status" --textbox "$temp_file" 20 80 2>&1 >/dev/null
    rm -f "$temp_file"
}

stop_all_containers() {
    # Always get fresh container list
    local running
    running=$(get_running_containers)
    
    if [ -z "$running" ]; then
        dialog --stdout --msgbox "No running containers to stop." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Convert to array
    local containers=()
    while IFS= read -r line; do
        [ -n "$line" ] && containers+=("$line")
    done <<< "$running"
    
    local total=${#containers[@]}
    
    dialog --stdout --yesno "Stop all MOAD containers?\n\nRunning containers:\n$running" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local failed_containers=()
        local success_count=0
        local fail_count=0
        
        # Process each container with individual progress
        for i in "${!containers[@]}"; do
            local container="${containers[$i]}"
            local container_num=$((i + 1))
            local percent=$((container_num * 100 / total))
            local display_name=$(echo "$container" | sed 's/^moad-//')
            
            # Show progress
            {
                echo "XXX"
                echo "$percent"
                echo "Stopping $display_name ($container_num/$total)..."
                echo "XXX"
            } | dialog --colors --gauge "Stopping containers... ($container_num/$total)" 8 60 0
            
            # Execute command outside subshell so variables persist
            local stderr_output
            stderr_output=$(docker compose stop "$container" 2>&1)
            local result=$?
            
            if [ $result -eq 0 ]; then
                success_count=$((success_count + 1))
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✓ $display_name stopped"
                    echo "XXX"
                } | dialog --colors --gauge "Stopping containers... ($container_num/$total)" 8 60 0
            else
                fail_count=$((fail_count + 1))
                failed_containers+=("$container")
                log_command_error "stop_all_containers" "docker compose stop $container" "$container" "$result" "$stderr_output"
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✗ $display_name failed"
                    echo "XXX"
                } | dialog --colors --gauge "Stopping containers... ($container_num/$total)" 8 60 0
            fi
        done
        
        if [ $fail_count -eq 0 ]; then
            dialog --stdout --msgbox "All containers stopped successfully.\n\nStopped: $success_count container(s)" 10 50 2>&1 >/dev/null
        else
            local error_msg="Some containers failed to stop.\n\nStopped: $success_count\nFailed: $fail_count\n\nFailed containers:\n$(printf '%s\n' "${failed_containers[@]}")"
            dialog --stdout --msgbox "$error_msg" 15 60 2>&1 >/dev/null
        fi
    fi
}

start_all_containers() {
    local stopped
    local all_containers
    stopped=$(get_stopped_containers)
    all_containers=$(get_all_containers)
    
    # If no containers exist at all, we need to create them
    if [ -z "$all_containers" ]; then
        # Validate environment variables before creating containers
        local validation_result
        validation_result=$(validate_env_variables 2>&1)
        local validation_status=$?
        
        if [ $validation_status -ne 0 ]; then
            if echo "$validation_result" | grep -q "MISSING_ENV_FILE"; then
                dialog --stdout --msgbox "Error: .env file not found.\n\nPlease use 'Generate .env File' option first." 10 50 2>&1 >/dev/null
                return
            elif echo "$validation_result" | grep -q "MISSING_VARS"; then
                local missing_vars
                missing_vars=$(echo "$validation_result" | sed 's/.*MISSING_VARS://')
                dialog --stdout --msgbox "Error: Missing required environment variables:\n\n$missing_vars\n\nPlease use 'Generate .env File' option." 12 60 2>&1 >/dev/null
                return
            fi
        fi
        
        dialog --stdout --yesno "No containers exist. Create and start all MOAD containers?\n\nThis will create and start:\n- vector\n- loki\n- prometheus\n- mysqld-exporter\n- grafana" 12 60 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            local result=1
            {
                echo "XXX"
                echo "0"
                echo "Creating containers..."
                echo "XXX"
                sleep 1
                
                echo "XXX"
                echo "50"
                echo "Starting containers..."
                echo "XXX"
                
                local stderr_output
                stderr_output=$(docker compose up -d 2>&1)
                result=$?
                
                if [ $result -eq 0 ]; then
                    echo "XXX"
                    echo "100"
                    echo "✓ All containers created and started successfully!"
                    echo "XXX"
                else
                    log_command_error "start_all_containers" "docker compose up -d" "" "$result" "$stderr_output"
                    echo "XXX"
                    echo "100"
                    echo "✗ Failed to create/start containers"
                    echo "XXX"
                fi
                sleep 1
            } | dialog --colors --gauge "Creating and starting containers..." 8 60 0
            
            if [ $result -eq 0 ]; then
                # Wait for containers to start, then verify using expected container names
                sleep 3
                local expected_containers=("moad-vector" "moad-loki" "moad-prometheus" "moad-mysqld-exporter" "moad-grafana")
                local total=${#expected_containers[@]}
                local success_count=0
                local fail_count=0
                local failed_containers=()
                
                # Verify each container (variables must be updated outside subshell)
                for i in "${!expected_containers[@]}"; do
                    local container="${expected_containers[$i]}"
                    local container_num=$((i + 1))
                    local percent=$((container_num * 100 / total))
                    local display_name=$(echo "$container" | sed 's/^moad-//')
                    local status
                    status=$(get_container_status_from_docker "$container")
                    
                    {
                        echo "XXX"
                        echo "$percent"
                        echo "Checking $display_name ($container_num/$total)..."
                        echo "XXX"
                    } | dialog --colors --gauge "Verifying containers..." 8 60 0
                    
                    if [ "$status" = "running" ]; then
                        success_count=$((success_count + 1))
                        {
                            echo "XXX"
                            echo "$percent"
                            echo "✓ $display_name: running"
                            echo "XXX"
                        } | dialog --colors --gauge "Verifying containers..." 8 60 0
                    else
                        fail_count=$((fail_count + 1))
                        failed_containers+=("$container ($status)")
                        log_error "start_all_containers" "Container $container status: $status" "$container"
                        {
                            echo "XXX"
                            echo "$percent"
                            echo "✗ $display_name: $status"
                            echo "XXX"
                        } | dialog --colors --gauge "Verifying containers..." 8 60 0
                    fi
                done
                
                # Final status
                {
                    echo "XXX"
                    echo "100"
                    if [ $fail_count -eq 0 ]; then
                        echo "All containers running!"
                    else
                        echo "Some containers not running ($fail_count/$total)"
                    fi
                    echo "XXX"
                    sleep 1
                } | dialog --colors --gauge "Verifying containers..." 8 60 0
                
                # Show final result (variables now have correct values)
                if [ $fail_count -eq 0 ]; then
                    dialog --stdout --msgbox "All containers created and started successfully!\n\nStarted: $success_count container(s)" 10 50 2>&1 >/dev/null
                else
                    local error_msg="Some containers failed to start.\n\nStarted: $success_count\nFailed: $fail_count\n\nFailed containers:\n$(printf '%s\n' "${failed_containers[@]}")"
                    dialog --stdout --msgbox "$error_msg" 15 60 2>&1 >/dev/null
                fi
            else
                dialog --stdout --msgbox "Error: Failed to create/start containers.\n\nCheck error log for details." 10 50 2>&1 >/dev/null
            fi
        fi
        return
    fi
    
    # If containers exist but none are stopped
    if [ -z "$stopped" ]; then
        dialog --stdout --msgbox "All containers are already running." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Convert to array
    local containers=()
    while IFS= read -r line; do
        [ -n "$line" ] && containers+=("$line")
    done <<< "$stopped"
    
    local total=${#containers[@]}
    
    # Start stopped containers
    dialog --stdout --yesno "Start all stopped MOAD containers?\n\nStopped containers:\n$stopped" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local failed_containers=()
        local success_count=0
        local fail_count=0
        
        # Process each container with individual progress
        for i in "${!containers[@]}"; do
            local container="${containers[$i]}"
            local container_num=$((i + 1))
            local percent=$((container_num * 100 / total))
            local display_name=$(echo "$container" | sed 's/^moad-//')
            
            # Show progress
            {
                echo "XXX"
                echo "$percent"
                echo "Starting $display_name ($container_num/$total)..."
                echo "XXX"
            } | dialog --colors --gauge "Starting containers... ($container_num/$total)" 8 60 0
            
            # Execute command outside subshell so variables persist
            local stderr_output
            stderr_output=$(docker compose start "$container" 2>&1)
            local result=$?
            
            if [ $result -eq 0 ]; then
                success_count=$((success_count + 1))
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✓ $display_name started"
                    echo "XXX"
                } | dialog --colors --gauge "Starting containers... ($container_num/$total)" 8 60 0
            else
                fail_count=$((fail_count + 1))
                failed_containers+=("$container")
                log_command_error "start_all_containers" "docker compose start $container" "$container" "$result" "$stderr_output"
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✗ $display_name failed"
                    echo "XXX"
                } | dialog --colors --gauge "Starting containers... ($container_num/$total)" 8 60 0
            fi
        done
        
        if [ $fail_count -eq 0 ]; then
            dialog --stdout --msgbox "All containers started successfully.\n\nStarted: $success_count container(s)" 10 50 2>&1 >/dev/null
        else
            local error_msg="Some containers failed to start.\n\nStarted: $success_count\nFailed: $fail_count\n\nFailed containers:\n$(printf '%s\n' "${failed_containers[@]}")"
            dialog --stdout --msgbox "$error_msg" 15 60 2>&1 >/dev/null
        fi
    fi
}

# Function to create and start containers (build if needed)
create_and_start_containers() {
    # Validate environment variables first
    local validation_result
    validation_result=$(validate_env_variables 2>&1)
    local validation_status=$?
    
    if [ $validation_status -ne 0 ]; then
        if echo "$validation_result" | grep -q "MISSING_ENV_FILE"; then
            dialog --stdout --msgbox "Error: .env file not found.\n\nPlease use 'Generate .env File' option first." 10 50 2>&1 >/dev/null
            return
        elif echo "$validation_result" | grep -q "MISSING_VARS"; then
            local missing_vars
            missing_vars=$(echo "$validation_result" | sed 's/.*MISSING_VARS://')
            dialog --stdout --msgbox "Error: Missing required environment variables in .env file:\n\n$missing_vars\n\nPlease use 'Generate .env File' option to update." 12 60 2>&1 >/dev/null
            return
        fi
    fi
    
    # Always get fresh container list
    local all_containers
    all_containers=$(get_all_containers)
    
    if [ -n "$all_containers" ]; then
        dialog --stdout --yesno "Containers already exist. Recreate and start all MOAD containers?\n\nThis will recreate:\n$all_containers\n\nExisting containers will be stopped and recreated." 14 60 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            return
        fi
    fi
    
    dialog --stdout --yesno "Create and start all MOAD containers?\n\nThis will:\n- Pull images (if needed)\n- Build images (if needed)\n- Create containers\n- Start all services" 12 60 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Step 1: Pull images with progress
    local images=("timberio/vector:0.38.0-alpine" "grafana/loki:2.9.0" "prom/prometheus:v2.48.0" "prom/mysqld-exporter:v0.15.1" "grafana/grafana:12.3.0")
    local image_names=("vector" "loki" "prometheus" "mysqld-exporter" "grafana")
    local total_images=${#images[@]}
    local pull_failed=0
    local pull_errors=()
    
    {
        for i in "${!images[@]}"; do
            local image_num=$((i + 1))
            local percent=$((image_num * 100 / total_images))
            local image_name="${image_names[$i]}"
            local image="${images[$i]}"
            
            echo "XXX"
            echo "$percent"
            echo "Pulling $image_name ($image_num/$total_images)..."
            echo "XXX"
            
            # Pull image and capture both stdout and stderr
            local pull_output
            pull_output=$(docker pull "$image" 2>&1)
            local pull_status=$?
            
            if [ $pull_status -eq 0 ]; then
                echo "XXX"
                echo "$percent"
                echo "✓ $image_name: Pulled"
                echo "XXX"
            else
                pull_failed=$((pull_failed + 1))
                pull_errors+=("$image_name: $pull_output")
                log_command_error "create_and_start_containers" "docker pull $image" "" "$pull_status" "$pull_output"
                echo "XXX"
                echo "$percent"
                echo "✗ $image_name: Pull failed"
                echo "XXX"
            fi
        done
        
        echo "XXX"
        echo "100"
        if [ $pull_failed -eq 0 ]; then
            echo "All images pulled successfully!"
        else
            echo "Some images failed to pull ($pull_failed/$total_images)"
        fi
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Pulling images... (Step 1/4)" 10 70 0
    
    if [ $pull_failed -gt 0 ]; then
        local error_msg="Image pull completed with errors:\n\n$(printf '%s\n' "${pull_errors[@]}" | head -5)\n\nContinue anyway?"
        dialog --stdout --yesno "$error_msg" 15 70 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            return
        fi
    fi
    
    # Step 2: Build images if needed (docker compose build)
    local services=("vector" "loki" "prometheus" "mysqld-exporter" "grafana")
    local total_services=${#services[@]}
    local build_failed=0
    local build_errors=()
    
    {
        for i in "${!services[@]}"; do
            local service_num=$((i + 1))
            local percent=$((service_num * 100 / total_services))
            local service="${services[$i]}"
            
            echo "XXX"
            echo "$percent"
            echo "Building $service ($service_num/$total_services)..."
            echo "XXX"
            
            # Build service and capture output
            local build_output
            build_output=$(docker compose build "$service" 2>&1)
            local build_status=$?
            
            if [ $build_status -eq 0 ]; then
                echo "XXX"
                echo "$percent"
                echo "✓ $service: Built"
                echo "XXX"
            else
                build_failed=$((build_failed + 1))
                build_errors+=("$service: $build_output")
                log_command_error "create_and_start_containers" "docker compose build $service" "$service" "$build_status" "$build_output"
                echo "XXX"
                echo "$percent"
                echo "✗ $service: Build failed"
                echo "XXX"
            fi
        done
        
        echo "XXX"
        echo "100"
        if [ $build_failed -eq 0 ]; then
            echo "All services built successfully!"
        else
            echo "Some services failed to build ($build_failed/$total_services)"
        fi
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Building images... (Step 2/4)" 10 70 0
    
    # Step 3: Create and start containers
    local stderr_output
    stderr_output=$(docker compose up -d 2>&1)
    local result=$?
    
    if [ $result -ne 0 ]; then
        log_command_error "create_and_start_containers" "docker compose up -d" "" "$result" "$stderr_output"
        dialog --stdout --msgbox "Error: Failed to create/start containers.\n\nError: $stderr_output\n\nCheck error log for details." 15 70 2>&1 >/dev/null
        return
    fi
    
    # Step 4: Verify container status
    # Wait a bit longer for containers to start
    sleep 3
    
    # Get expected container names from docker-compose.yml
    local expected_containers=("moad-vector" "moad-loki" "moad-prometheus" "moad-mysqld-exporter" "moad-grafana")
    local total=${#expected_containers[@]}
    local success_count=0
    local fail_count=0
    local failed_containers=()
    
    # Verify each container and capture results
    for i in "${!expected_containers[@]}"; do
        local container="${expected_containers[$i]}"
        local container_num=$((i + 1))
        local percent=$((container_num * 100 / total))
        local display_name=$(echo "$container" | sed 's/^moad-//')
        local status
        status=$(get_container_status_from_docker "$container")
        
        {
            echo "XXX"
            echo "$percent"
            echo "Checking $display_name ($container_num/$total)..."
            echo "XXX"
            sleep 0.3
        } | dialog --colors --gauge "Verifying containers... (Step 4/4)" 8 60 0
        
        if [ "$status" = "running" ]; then
            success_count=$((success_count + 1))
            {
                echo "XXX"
                echo "$percent"
                echo "✓ $display_name: running"
                echo "XXX"
            } | dialog --colors --gauge "Verifying containers... (Step 4/4)" 8 60 0
        elif [ "$status" = "not_found" ]; then
            fail_count=$((fail_count + 1))
            failed_containers+=("$container (not found)")
            log_error "create_and_start_containers" "Container $container not found after creation" "$container"
            {
                echo "XXX"
                echo "$percent"
                echo "✗ $display_name: not found"
                echo "XXX"
            } | dialog --colors --gauge "Verifying containers... (Step 4/4)" 8 60 0
        else
            fail_count=$((fail_count + 1))
            failed_containers+=("$container ($status)")
            log_error "create_and_start_containers" "Container $container status: $status" "$container"
            {
                echo "XXX"
                echo "$percent"
                echo "✗ $display_name: $status"
                echo "XXX"
            } | dialog --colors --gauge "Verifying containers... (Step 4/4)" 8 60 0
        fi
    done
    
    # Final status
    {
        echo "XXX"
        echo "100"
        if [ $fail_count -eq 0 ]; then
            echo "All containers running!"
        else
            echo "Some containers not running ($fail_count/$total)"
        fi
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Verifying containers... (Step 4/4)" 8 60 0
    
    # Show final result
    if [ $fail_count -eq 0 ]; then
        dialog --stdout --msgbox "All containers created and started successfully!\n\nStarted: $success_count container(s)" 10 50 2>&1 >/dev/null
    else
        local error_msg="Some containers failed to start.\n\nStarted: $success_count\nFailed: $fail_count\n\nFailed containers:\n$(printf '%s\n' "${failed_containers[@]}")"
        dialog --stdout --msgbox "$error_msg\n\nCheck error log and container logs for details." 15 60 2>&1 >/dev/null
    fi
}

restart_all_containers() {
    # Always get fresh container list
    local all_containers
    all_containers=$(get_all_containers)
    
    if [ -z "$all_containers" ]; then
        dialog --stdout --msgbox "No containers found." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Convert to array
    local containers=()
    while IFS= read -r line; do
        [ -n "$line" ] && containers+=("$line")
    done <<< "$all_containers"
    
    local total=${#containers[@]}
    
    dialog --stdout --yesno "Restart all MOAD containers?\n\nContainers:\n$all_containers" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local failed_containers=()
        local success_count=0
        local fail_count=0
        
        # Process each container with individual progress
        for i in "${!containers[@]}"; do
            local container="${containers[$i]}"
            local container_num=$((i + 1))
            local percent=$((container_num * 100 / total))
            local display_name=$(echo "$container" | sed 's/^moad-//')
            
            # Show progress
            {
                echo "XXX"
                echo "$percent"
                echo "Restarting $display_name ($container_num/$total)..."
                echo "XXX"
            } | dialog --colors --gauge "Restarting containers... ($container_num/$total)" 8 60 0
            
            # Execute command outside subshell so variables persist
            local stderr_output
            stderr_output=$(docker compose restart "$container" 2>&1)
            local result=$?
            
            if [ $result -eq 0 ]; then
                success_count=$((success_count + 1))
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✓ $display_name restarted"
                    echo "XXX"
                } | dialog --colors --gauge "Restarting containers... ($container_num/$total)" 8 60 0
            else
                fail_count=$((fail_count + 1))
                failed_containers+=("$container")
                log_command_error "restart_all_containers" "docker compose restart $container" "$container" "$result" "$stderr_output"
                {
                    echo "XXX"
                    echo "$percent"
                    echo "✗ $display_name failed"
                    echo "XXX"
                } | dialog --colors --gauge "Restarting containers... ($container_num/$total)" 8 60 0
            fi
        done
        
        if [ $fail_count -eq 0 ]; then
            dialog --stdout --msgbox "All containers restarted successfully.\n\nRestarted: $success_count container(s)" 10 50 2>&1 >/dev/null
        else
            local error_msg="Some containers failed to restart.\n\nRestarted: $success_count\nFailed: $fail_count\n\nFailed containers:\n$(printf '%s\n' "${failed_containers[@]}")"
            dialog --stdout --msgbox "$error_msg" 15 60 2>&1 >/dev/null
        fi
    fi
}

restart_individual_container() {
    local containers
    local menu_items=()
    
    containers=$(get_all_containers)
    
    if [ -z "$containers" ]; then
        dialog --stdout --msgbox "No containers found." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Build menu items array
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            local status
            status=$(docker compose ps --format "{{.Status}}" --filter "name=$container" 2>/dev/null | head -1)
            menu_items+=("$container" "$status")
        fi
    done <<< "$containers"
    
    if [ ${#menu_items[@]} -eq 0 ]; then
        dialog --stdout --msgbox "No containers available." 8 50 2>&1 >/dev/null
        return
    fi
    
    local selected
    local exit_code
    selected=$(dialog --stdout --title "Select Container to Restart" \
        --menu "Choose a container to restart:" 15 60 10 \
        "${menu_items[@]}" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    dialog --stdout --yesno "Restart container: $selected?" 8 50 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        dialog --stdout --infobox "Restarting $selected..." 5 50 2>&1 >/dev/null
        local stderr_output
        stderr_output=$(docker compose restart "$selected" 2>&1)
        local result=$?
        
        if [ $result -eq 0 ]; then
            dialog --stdout --msgbox "Container $selected restarted successfully." 8 50 2>&1 >/dev/null
        else
            log_command_error "restart_individual_container" "docker compose restart $selected" "$selected" "$result" "$stderr_output"
            dialog --stdout --msgbox "Error: Failed to restart $selected.\n\nCheck error log for details." 10 50 2>&1 >/dev/null
        fi
    fi
}

view_container_logs() {
    local containers
    local menu_items=()
    
    containers=$(get_all_containers)
    
    if [ -z "$containers" ]; then
        dialog --stdout --msgbox "No containers found." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Build menu items array
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            local status
            status=$(docker compose ps --format "{{.Status}}" --filter "name=$container" 2>/dev/null | head -1)
            menu_items+=("$container" "$status")
        fi
    done <<< "$containers"
    
    if [ ${#menu_items[@]} -eq 0 ]; then
        dialog --stdout --msgbox "No containers available." 8 50 2>&1 >/dev/null
        return
    fi
    
    local selected
    local exit_code
    selected=$(dialog --stdout --title "Select Container for Logs" \
        --menu "Choose a container to view logs:" 15 60 10 \
        "${menu_items[@]}" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    local lines
    lines=$(dialog --stdout --inputbox "Number of log lines to show (default: 100):" 8 50 "100" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ]; then
        return
    fi
    lines=${lines:-100}
    
    dialog --stdout --infobox "Fetching logs for $selected..." 5 50 2>&1 >/dev/null
    local logs
    local stderr_output
    logs=$(docker compose logs --tail="$lines" "$selected" 2>&1)
    local result=$?
    
    if [ $result -ne 0 ]; then
        log_command_error "view_container_logs" "docker compose logs --tail=$lines $selected" "$selected" "$result" "$logs"
    fi
    
    if [ -z "$logs" ]; then
        logs="No logs available for $selected"
    fi
    
    # Use temporary file for dialog textbox (cannot use process substitution)
    local temp_file
    temp_file=$(mktemp /tmp/moad-logs-XXXXXX)
    echo "$logs" > "$temp_file"
    
    dialog --stdout --title "Logs: $selected" --textbox "$temp_file" 25 80 2>&1 >/dev/null
    rm -f "$temp_file"
}

view_recent_errors() {
    local temp_error_file
    temp_error_file=$(mktemp /tmp/moad-errors-XXXXXX)
    local has_errors=false
    
    # Show MOAD Manager error log
    if [ -f "$ERROR_LOG" ]; then
        local manager_errors
        manager_errors=$(tail -50 "$ERROR_LOG" 2>/dev/null)
        if [ -n "$manager_errors" ]; then
            echo "=== MOAD Manager Error Log (last 50 lines) ===" >> "$temp_error_file"
            echo "$manager_errors" >> "$temp_error_file"
            echo "" >> "$temp_error_file"
            has_errors=true
        fi
    fi
    
    # Get fresh container list
    local containers
    containers=$(get_all_containers)
    
    if [ -n "$containers" ]; then
        dialog --stdout --infobox "Scanning container logs for errors..." 5 50 2>&1 >/dev/null
        
        local container_error_count=0
        while IFS= read -r container; do
            if [ -n "$container" ]; then
                # Check container status for errors
                local status
                status=$(get_container_status_from_docker "$container")
                
                # Check if container is unhealthy or exited
                if [ "$status" != "running" ] && [ "$status" != "not_found" ]; then
                    if [ $container_error_count -eq 0 ]; then
                        echo "=== Container Status Errors ===" >> "$temp_error_file"
                    fi
                    echo "" >> "$temp_error_file"
                    echo "$container: Status=$status" >> "$temp_error_file"
                    container_error_count=$((container_error_count + 1))
                    has_errors=true
                fi
                
                # Check container logs for error patterns
                local log_errors
                log_errors=$(docker compose logs --tail=20 "$container" 2>&1 | grep -iE "error|fatal|exception|failed|panic|crash" | head -5)
                if [ -n "$log_errors" ]; then
                    if [ $container_error_count -eq 0 ]; then
                        echo "=== Container Log Errors ===" >> "$temp_error_file"
                    fi
                    echo "" >> "$temp_error_file"
                    echo "--- $container ---" >> "$temp_error_file"
                    echo "$log_errors" >> "$temp_error_file"
                    container_error_count=$((container_error_count + 1))
                    has_errors=true
                fi
            fi
        done <<< "$containers"
    fi
    
    if [ "$has_errors" = "false" ]; then
        echo "No recent errors found." >> "$temp_error_file"
        echo "" >> "$temp_error_file"
        echo "- MOAD Manager error log: $ERROR_LOG" >> "$temp_error_file"
        echo "- Container logs: No errors detected" >> "$temp_error_file"
    else
        echo "" >> "$temp_error_file"
        echo "Note: For detailed container logs, use 'View Container Logs' option." >> "$temp_error_file"
    fi
    
    # Add file location at the top for easy copying
    {
        echo "=== Error Log File Location (for copying) ==="
        echo "$temp_error_file"
        echo ""
        echo "=== Error Details (scroll with arrow keys) ==="
        echo ""
        cat "$temp_error_file"
    } > "${temp_error_file}.display"
    
    # Use textbox for better scrolling (though text selection is still limited in dialog)
    dialog --stdout --title "Recent Errors" --textbox "${temp_error_file}.display" 30 90 2>&1 >/dev/null
    
    # Ask if user wants to keep the file
    dialog --stdout --yesno "Error log saved to:\n\n$temp_error_file\n\nKeep this file for later reference?\n\n(You can copy text from the file using: cat $temp_error_file)" 12 70 2>&1 >/dev/null
    local keep_file=$?
    
    if [ $keep_file -ne 0 ]; then
        rm -f "$temp_error_file" "${temp_error_file}.display"
    else
        dialog --stdout --msgbox "Error log kept at:\n\n$temp_error_file\n\nYou can view it with: cat $temp_error_file\n\nOr copy it to your clipboard from another terminal." 10 70 2>&1 >/dev/null
    fi
}

pull_latest_images() {
    dialog --stdout --yesno "Pull latest images for all MOAD services?" 8 50 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    
    local images=("timberio/vector:0.38.0-alpine" "grafana/loki:2.9.0" "prom/prometheus:v2.48.0" "prom/mysqld-exporter:v0.15.1" "grafana/grafana:12.3.0")
    local image_names=("vector" "loki" "prometheus" "mysqld-exporter" "grafana")
    local total=${#images[@]}
    local pull_failed=0
    local pull_errors=()
    
    # Create progress display
    {
        for i in "${!images[@]}"; do
            local image_num=$((i + 1))
            local percent=$((image_num * 100 / total))
            local image_name="${image_names[$i]}"
            local image="${images[$i]}"
            
            echo "XXX"
            echo "$percent"
            echo "Pulling $image_name ($image_num/$total)..."
            echo "XXX"
            
            # Pull the image and capture both stdout and stderr
            local pull_output
            pull_output=$(docker pull "$image" 2>&1)
            local pull_status=$?
            
            if [ $pull_status -eq 0 ]; then
                echo "XXX"
                echo "$percent"
                echo "✓ $image_name: Pulled"
                echo "XXX"
            else
                pull_failed=$((pull_failed + 1))
                pull_errors+=("$image_name: $pull_output")
                log_command_error "pull_latest_images" "docker pull $image" "" "$pull_status" "$pull_output"
                echo "XXX"
                echo "$percent"
                echo "✗ $image_name: Pull failed"
                echo "XXX"
            fi
        done
        
        echo "XXX"
        echo "100"
        if [ $pull_failed -eq 0 ]; then
            echo "All images pulled successfully!"
        else
            echo "Some images failed to pull ($pull_failed/$total)"
        fi
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Pulling latest images..." 10 70 0
    
    if [ $pull_failed -eq 0 ]; then
        dialog --stdout --msgbox "Image pull completed successfully.\n\nPulled: $total image(s)" 10 50 2>&1 >/dev/null
    else
        local error_msg="Image pull completed with errors.\n\nPulled: $((total - pull_failed))/$total\nFailed: $pull_failed\n\nErrors:\n$(printf '%s\n' "${pull_errors[@]}" | head -3)"
        dialog --stdout --msgbox "$error_msg\n\nCheck error log for details." 15 70 2>&1 >/dev/null
    fi
}

complete_prune_purge() {
    dialog --stdout --yesno "WARNING: This will:\n\n- Stop all MOAD containers\n- Remove all containers\n- Remove all volumes\n- Remove all networks\n- Prune all unused Docker resources\n\nThis is DESTRUCTIVE and cannot be undone!\n\nContinue?" 15 70 2>&1 >/dev/null
    
    if [ $? -ne 0 ]; then
        return
    fi
    
    local errors=()
    
    {
        echo "XXX"
        echo "10"
        echo "Stopping and removing containers..."
        echo "XXX"
        
        local stderr_output
        stderr_output=$(docker compose down 2>&1)
        local result=$?
        if [ $result -ne 0 ]; then
            errors+=("docker compose down: $stderr_output")
            log_command_error "complete_prune_purge" "docker compose down" "" "$result" "$stderr_output"
        fi
        
        echo "XXX"
        echo "30"
        echo "Removing containers..."
        echo "XXX"
        
        stderr_output=$(docker container prune -f 2>&1)
        result=$?
        if [ $result -ne 0 ]; then
            errors+=("docker container prune: $stderr_output")
            log_command_error "complete_prune_purge" "docker container prune -f" "" "$result" "$stderr_output"
        fi
        
        echo "XXX"
        echo "50"
        echo "Removing volumes..."
        echo "XXX"
        
        stderr_output=$(docker volume prune -f 2>&1)
        result=$?
        if [ $result -ne 0 ]; then
            errors+=("docker volume prune: $stderr_output")
            log_command_error "complete_prune_purge" "docker volume prune -f" "" "$result" "$stderr_output"
        fi
        
        echo "XXX"
        echo "70"
        echo "Removing networks..."
        echo "XXX"
        
        stderr_output=$(docker network prune -f 2>&1)
        result=$?
        if [ $result -ne 0 ]; then
            errors+=("docker network prune: $stderr_output")
            log_command_error "complete_prune_purge" "docker network prune -f" "" "$result" "$stderr_output"
        fi
        
        echo "XXX"
        echo "90"
        echo "Pruning system resources..."
        echo "XXX"
        
        stderr_output=$(docker system prune -af --volumes 2>&1)
        result=$?
        if [ $result -ne 0 ]; then
            errors+=("docker system prune: $stderr_output")
            log_command_error "complete_prune_purge" "docker system prune -af --volumes" "" "$result" "$stderr_output"
        fi
        
        echo "XXX"
        echo "100"
        if [ ${#errors[@]} -eq 0 ]; then
            echo "✓ Prune and purge completed"
        else
            echo "⚠ Completed with ${#errors[@]} error(s)"
        fi
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Pruning and purging Docker resources..." 8 60 0
    
    if [ ${#errors[@]} -eq 0 ]; then
        dialog --stdout --msgbox "Complete Docker cleanup finished.\n\nAll containers, volumes, and networks have been removed." 10 60 2>&1 >/dev/null
    else
        local error_msg="Prune and purge completed with errors:\n\n$(printf '%s\n' "${errors[@]}" | head -3)\n\nCheck error log for details."
        dialog --stdout --msgbox "$error_msg" 15 70 2>&1 >/dev/null
    fi
}

# ============================================================================
# SERVICE INFORMATION & HEALTH CHECKS
# ============================================================================

show_service_urls() {
    local grafana_pass
    grafana_pass=$(read_env_value "GRAFANA_ADMIN_PASSWORD")
    
    local info="MOAD Service URLs:\n\n"
    info+="Grafana (Visualization):\n"
    info+="  URL: ${GRAFANA_URL}\n"
    info+="  Username: admin\n"
    if [ -n "$grafana_pass" ]; then
        info+="  Password: ${grafana_pass}\n"
    else
        info+="  Password: (check .env file)\n"
    fi
    info+="\n"
    info+="Prometheus (Metrics):\n"
    info+="  Internal: http://moad-prometheus:9090\n"
    info+="  Access via Grafana datasource\n"
    info+="\n"
    info+="Loki (Logs):\n"
    info+="  Internal: http://moad-loki:3100\n"
    info+="  Access via Grafana datasource\n"
    info+="\n"
    info+="MySQL Exporter:\n"
    info+="  Internal: http://moad-mysqld-exporter:9104\n"
    info+="  Metrics scraped by Prometheus\n"
    
    local temp_file
    temp_file=$(mktemp /tmp/moad-urls-XXXXXX)
    echo -e "$info" > "$temp_file"
    dialog --stdout --title "Service URLs" --textbox "$temp_file" 18 70 2>&1 >/dev/null
    rm -f "$temp_file"
}

check_service_health() {
    local health_info="Service Health Check:\n\n"
    local all_healthy=true
    
    # Helper function to check container health
    check_container_health() {
        local container_name=$1
        local service_name=$2
        
        # Check if container exists and is running
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)
        
        if [ -z "$status" ]; then
            echo "✗ $service_name: Container not found"
            return 1
        elif [ "$status" = "running" ]; then
            # Check health status if healthcheck is configured
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ "$health" = "healthy" ]; then
                echo "✓ $service_name: Healthy"
                return 0
            elif [ "$health" = "unhealthy" ]; then
                echo "✗ $service_name: Unhealthy"
                return 1
            elif [ "$health" = "starting" ]; then
                echo "⚠ $service_name: Starting (health check in progress)"
                return 1
            elif [ -z "$health" ] || [ "$health" = "<no value>" ]; then
                # No healthcheck configured, just check if running
                echo "✓ $service_name: Running (no healthcheck)"
                return 0
            else
                echo "? $service_name: Status=$health"
                return 1
            fi
        else
            echo "✗ $service_name: $status"
            return 1
        fi
    }
    
    # Check Grafana (external access)
    dialog --stdout --infobox "Checking Grafana (1/5)..." 5 50 2>&1 >/dev/null
    local grafana_result
    grafana_result=$(check_container_health "moad-grafana" "Grafana")
    if [ $? -eq 0 ]; then
        health_info+="$grafana_result\n"
    else
        health_info+="$grafana_result\n"
        all_healthy=false
    fi
    
    # Check Prometheus (internal only)
    dialog --stdout --infobox "Checking Prometheus (2/5)..." 5 50 2>&1 >/dev/null
    local prometheus_result
    prometheus_result=$(check_container_health "moad-prometheus" "Prometheus")
    if [ $? -eq 0 ]; then
        health_info+="$prometheus_result\n"
    else
        health_info+="$prometheus_result\n"
        all_healthy=false
    fi
    
    # Check Loki (internal only)
    dialog --stdout --infobox "Checking Loki (3/5)..." 5 50 2>&1 >/dev/null
    local loki_result
    loki_result=$(check_container_health "moad-loki" "Loki")
    if [ $? -eq 0 ]; then
        health_info+="$loki_result\n"
    else
        health_info+="$loki_result\n"
        all_healthy=false
    fi
    
    # Check MySQL Exporter (internal only)
    dialog --stdout --infobox "Checking MySQL Exporter (4/5)..." 5 50 2>&1 >/dev/null
    local mysql_exporter_result
    mysql_exporter_result=$(check_container_health "moad-mysqld-exporter" "MySQL Exporter")
    if [ $? -eq 0 ]; then
        health_info+="$mysql_exporter_result\n"
    else
        health_info+="$mysql_exporter_result\n"
        all_healthy=false
    fi
    
    # Check Vector (internal only)
    dialog --stdout --infobox "Checking Vector (5/5)..." 5 50 2>&1 >/dev/null
    local vector_result
    vector_result=$(check_container_health "moad-vector" "Vector")
    if [ $? -eq 0 ]; then
        health_info+="$vector_result\n"
    else
        health_info+="$vector_result\n"
        all_healthy=false
    fi
    
    health_info+="\n"
    if [ "$all_healthy" = true ]; then
        health_info+="Overall Status: All services healthy ✓"
    else
        health_info+="Overall Status: Some services unhealthy ✗"
    fi
    
    # Use temporary file for dialog textbox (cannot use process substitution)
    local temp_file
    temp_file=$(mktemp /tmp/moad-health-XXXXXX)
    echo -e "$health_info" > "$temp_file"
    
    dialog --stdout --title "Service Health" --textbox "$temp_file" 15 60 2>&1 >/dev/null
    rm -f "$temp_file"
}

test_mysql_connectivity() {
    local mysql_host
    local mysql_user
    local mysql_pass
    
    mysql_host=$(read_env_value "MYSQL_HOST")
    mysql_user=$(read_env_value "MYSQL_MOAD_RO_USER")
    mysql_pass=$(read_env_value "MYSQL_MOAD_RO_PASSWORD")
    
    if [ -z "$mysql_host" ] || [ -z "$mysql_user" ] || [ -z "$mysql_pass" ]; then
        dialog --stdout --msgbox "MySQL configuration not found in .env file.\n\nPlease generate .env file first." 10 50 2>&1 >/dev/null
        return
    fi
    
    dialog --stdout --infobox "Testing MySQL connectivity..." 5 50 2>&1 >/dev/null
    
    # Test connection using docker run with mysql client
    local result
    result=$(docker run --rm --network moad_moad-network mysql:8.0 mysql \
        -h"$mysql_host" -u"$mysql_user" -p"$mysql_pass" \
        -e "SELECT 1;" 2>&1)
    
    if [ $? -eq 0 ]; then
        local success_msg="MySQL Connection: SUCCESS\n\nHost: $mysql_host\nUser: $mysql_user\n\nConnection test passed."
        local temp_file
        temp_file=$(mktemp /tmp/moad-mysql-XXXXXX)
        echo -e "$success_msg" > "$temp_file"
        dialog --stdout --title "MySQL Connectivity Test" --textbox "$temp_file" 10 60 2>&1 >/dev/null
        rm -f "$temp_file"
    else
        local error_msg="MySQL Connection: FAILED\n\nError details:\n$result\n\nPlease check:\n- MySQL host is correct\n- User credentials are correct\n- Network connectivity"
        local temp_file
        temp_file=$(mktemp /tmp/moad-mysql-XXXXXX)
        echo -e "$error_msg" > "$temp_file"
        dialog --stdout --title "MySQL Connectivity Test" --textbox "$temp_file" 15 70 2>&1 >/dev/null
        rm -f "$temp_file"
    fi
}

# ============================================================================
# SYSTEM MONITORING
# ============================================================================

show_disk_usage() {
    local disk_info
    disk_info=$(df -h / 2>/dev/null | tail -1)
    local docker_info
    docker_info=$(docker system df 2>/dev/null || echo "Docker info unavailable")
    
    local info="Disk Usage:\n\n"
    info+="System:\n$disk_info\n\n"
    info+="Docker:\n$docker_info"
    
    local temp_file
    temp_file=$(mktemp /tmp/moad-disk-XXXXXX)
    echo -e "$info" > "$temp_file"
    dialog --stdout --title "Disk Usage" --textbox "$temp_file" 15 70 2>&1 >/dev/null
    rm -f "$temp_file"
}

show_system_resources() {
    local cpu_info
    cpu_info=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    local mem_info
    mem_info=$(free -h | grep Mem | awk '{printf "Used: %s / %s (%.1f%%)", $3, $2, ($3/$2)*100}')
    local load_info
    load_info=$(uptime | awk -F'load average:' '{print $2}')
    
    local info="System Resources:\n\n"
    info+="CPU Usage: ${cpu_info}\n"
    info+="Memory: ${mem_info}\n"
    info+="Load Average: ${load_info}\n"
    
    local temp_file
    temp_file=$(mktemp /tmp/moad-resources-XXXXXX)
    echo -e "$info" > "$temp_file"
    dialog --stdout --title "System Resources" --textbox "$temp_file" 10 60 2>&1 >/dev/null
    rm -f "$temp_file"
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

view_configuration_files() {
    local menu_items=(
        "docker-compose.yml" "Docker Compose configuration"
        "vector/vector.yml" "Vector log processing config"
        "prometheus/prometheus.yml" "Prometheus metrics config"
        "loki/loki-config.yml" "Loki log aggregation config"
        "grafana/provisioning/datasources/datasources.yml" "Grafana datasources config"
        "grafana/provisioning/dashboards/dashboards.yml" "Grafana dashboards config"
    )
    
    local selected
    local exit_code
    selected=$(dialog --stdout --title "View Configuration" \
        --menu "Select a configuration file to view:" 15 60 7 \
        "${menu_items[@]}" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    if [ -f "$selected" ]; then
        # Use temporary file for dialog textbox (cannot use process substitution)
        local temp_file
        temp_file=$(mktemp /tmp/moad-config-XXXXXX)
        cat "$selected" > "$temp_file" 2>/dev/null || echo "Error reading file" > "$temp_file"
        
        dialog --stdout --title "Config: $selected" --textbox "$temp_file" 25 80 2>&1 >/dev/null
        rm -f "$temp_file"
    else
        dialog --stdout --msgbox "File not found: $selected" 8 50 2>&1 >/dev/null
    fi
}

# ============================================================================
# BACKUP AND RESTORE FUNCTIONS
# ============================================================================

backup_moad_config() {
    # Show warning about sensitive information
    dialog --stdout --yesno "WARNING: This backup will contain sensitive information including:\n\n- MySQL passwords\n- Grafana admin passwords\n- All configuration files\n\nEnsure backup files are stored securely.\n\nContinue with backup?" 12 70 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Get backup file path
    local backup_file
    local default_file="moad-backup-$(date +%Y%m%d-%H%M%S).json"
    backup_file=$(dialog --stdout --inputbox "Backup file path:" 10 60 "$default_file" 2>&1)
    local exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$backup_file" ]; then
        return
    fi
    
    # Ensure .json extension
    if [[ ! "$backup_file" =~ \.json$ ]]; then
        backup_file="${backup_file}.json"
    fi
    
    dialog --stdout --infobox "Creating backup..." 5 50 2>&1 >/dev/null
    
    # Create temporary directory for file collection
    local temp_dir
    temp_dir=$(mktemp -d)
    local backup_data="{}"
    
    # Function to encode file to base64 and add to JSON
    add_file_to_backup() {
        local file_path=$1
        local json_key=$2
        
        if [ -f "$file_path" ]; then
            local file_content
            file_content=$(base64 -w 0 < "$file_path" 2>/dev/null || base64 < "$file_path" 2>/dev/null)
            local file_size
            file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
            
            # Use jq if available, otherwise use sed/awk
            if [ "$HAS_JQ" = "true" ] && command -v jq >/dev/null 2>&1; then
                backup_data=$(echo "$backup_data" | jq --arg key "$json_key" --arg content "$file_content" --arg size "$file_size" --arg path "$file_path" '. + {($key): {"content": $content, "size": $size, "path": $path}}')
            else
                # Fallback: simple JSON construction
                # Escape special characters in base64 content for JSON
                local escaped_content
                escaped_content=$(echo "$file_content" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\$/\\$/g' | sed 's/`/\\`/g')
                local entry="\"$json_key\":{\"content\":\"$escaped_content\",\"size\":\"$file_size\",\"path\":\"$file_path\"}"
                if [ "$backup_data" = "{}" ]; then
                    backup_data="{${entry}}"
                else
                    # Remove trailing } and add comma, then add entry and closing }
                    backup_data=$(echo "$backup_data" | sed 's/}$//')
                    backup_data="${backup_data},${entry}}"
                fi
            fi
        fi
    }
    
    # Backup all configuration files
    add_file_to_backup ".env" "env_file"
    add_file_to_backup "docker-compose.yml" "docker_compose"
    add_file_to_backup "vector/vector.yml" "vector_config"
    add_file_to_backup "prometheus/prometheus.yml" "prometheus_config"
    add_file_to_backup "loki/loki-config.yml" "loki_config"
    add_file_to_backup "grafana/provisioning/datasources/datasources.yml" "grafana_datasources"
    add_file_to_backup "grafana/provisioning/dashboards/dashboards.yml" "grafana_dashboards_provisioning"
    
    # Backup all Grafana dashboard JSON files
    local dashboard_count=0
    for dashboard in grafana/dashboards/*.json; do
        if [ -f "$dashboard" ]; then
            local dashboard_name
            dashboard_name=$(basename "$dashboard" .json)
            add_file_to_backup "$dashboard" "grafana_dashboard_${dashboard_name}"
            dashboard_count=$((dashboard_count + 1))
        fi
    done
    
    # Validate that backup_data contains files
    if [ "$backup_data" = "{}" ]; then
        dialog --stdout --msgbox "Error: No files were added to backup.\n\nPlease check that configuration files exist." 10 60 2>&1 >/dev/null
        rm -rf "$temp_dir"
        return
    fi
    
    # Create backup JSON structure
    local backup_json
    if [ "$HAS_JQ" = "true" ] && command -v jq >/dev/null 2>&1; then
        backup_json=$(cat <<EOF
{
  "moad_backup": {
    "version": "1.0",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "files": $backup_data,
    "metadata": {
      "dashboard_count": $dashboard_count,
      "backup_created_by": "moad-manager.sh"
    }
  }
}
EOF
)
    else
        # Fallback JSON construction
        backup_json=$(cat <<EOF
{
  "moad_backup": {
    "version": "1.0",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "files": $backup_data,
    "metadata": {
      "dashboard_count": $dashboard_count,
      "backup_created_by": "moad-manager.sh"
    }
  }
}
EOF
)
    fi
    
    # Write backup file
    echo "$backup_json" > "$backup_file"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    local file_size_human
    file_size_human=$(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "${file_size} bytes")
    
    dialog --stdout --msgbox "Backup created successfully!\n\nFile: $backup_file\nSize: $file_size_human\n\n⚠️  WARNING: This file contains sensitive information.\nStore it securely!" 12 70 2>&1 >/dev/null
}

restore_moad_config() {
    # Show warning
    dialog --stdout --yesno "WARNING: This will overwrite existing configuration files!\n\n- .env file\n- docker-compose.yml\n- All service configuration files\n- Grafana dashboards\n\nMake sure you have a backup of current configuration.\n\nContinue with restore?" 14 70 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Get backup file path
    local backup_file
    backup_file=$(dialog --stdout --fselect "$(pwd)/" 20 70 2>&1)
    local exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$backup_file" ]; then
        return
    fi
    
    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        dialog --stdout --msgbox "Error: Backup file not found:\n$backup_file" 8 60 2>&1 >/dev/null
        return
    fi
    
    # Validate JSON and extract file list
    dialog --stdout --infobox "Validating backup file..." 5 50 2>&1 >/dev/null
    
    # Check if jq is available for better parsing
    if [ "$HAS_JQ" = "true" ] && command -v jq >/dev/null 2>&1; then
        # Validate JSON structure
        if ! jq empty "$backup_file" 2>/dev/null; then
            dialog --stdout --msgbox "Error: Invalid JSON backup file." 8 50 2>&1 >/dev/null
            return
        fi
        
        # Check if it's a MOAD backup
        if ! jq -e '.moad_backup' "$backup_file" >/dev/null 2>&1; then
            dialog --stdout --msgbox "Error: Not a valid MOAD backup file." 8 50 2>&1 >/dev/null
            return
        fi
        
        # Get backup info
        local backup_version
        backup_version=$(jq -r '.moad_backup.version' "$backup_file" 2>/dev/null)
        local backup_timestamp
        backup_timestamp=$(jq -r '.moad_backup.timestamp' "$backup_file" 2>/dev/null)
        local backup_hostname
        backup_hostname=$(jq -r '.moad_backup.hostname' "$backup_file" 2>/dev/null)
        
        # Show backup info and confirm
        dialog --stdout --yesno "Backup Information:\n\nVersion: $backup_version\nCreated: $backup_timestamp\nHostname: $backup_hostname\n\nRestore this backup?" 12 60 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            return
        fi
        
        # Restore files
        dialog --stdout --infobox "Restoring configuration files..." 5 50 2>&1 >/dev/null
        
        local restore_count=0
        local error_count=0
        local temp_restore_file
        temp_restore_file=$(mktemp)
        
        # Get all file keys from backup and restore them
        jq -r '.moad_backup.files | keys[]' "$backup_file" 2>/dev/null > "$temp_restore_file"
        
        while IFS= read -r file_key; do
            [ -z "$file_key" ] && continue
            
            local file_path
            file_path=$(jq -r ".moad_backup.files[\"$file_key\"].path" "$backup_file" 2>/dev/null)
            local file_content
            file_content=$(jq -r ".moad_backup.files[\"$file_key\"].content" "$backup_file" 2>/dev/null)
            
            if [ -n "$file_path" ] && [ -n "$file_content" ] && [ "$file_path" != "null" ] && [ "$file_content" != "null" ]; then
                # Create directory if needed
                local file_dir
                file_dir=$(dirname "$file_path")
                mkdir -p "$file_dir" 2>/dev/null
                
                # Decode and write file
                echo "$file_content" | base64 -d > "$file_path" 2>/dev/null || echo "$file_content" | base64 -D > "$file_path" 2>/dev/null
                if [ $? -eq 0 ]; then
                    restore_count=$((restore_count + 1))
                else
                    error_count=$((error_count + 1))
                fi
            fi
        done < "$temp_restore_file"
        
        rm -f "$temp_restore_file"
        
        if [ $error_count -eq 0 ]; then
            dialog --stdout --msgbox "Restore completed successfully!\n\nRestored $restore_count file(s).\n\nNext steps:\n1. Review restored files\n2. Start MOAD stack" 12 60 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Restore completed with errors.\n\nRestored: $restore_count file(s)\nErrors: $error_count file(s)" 10 60 2>&1 >/dev/null
        fi
    else
        # Fallback: basic JSON parsing without jq (limited but functional)
        dialog --stdout --msgbox "Warning: 'jq' not found. Using basic JSON parsing.\n\nFor best results, install jq:\nsudo apt-get install jq\n\nAttempting restore anyway..." 12 60 2>&1 >/dev/null
        
        # Basic restore using grep/sed (less reliable)
        local restore_count=0
        
        # Extract .env file
        if grep -q '"env_file"' "$backup_file"; then
            local env_content
            env_content=$(grep -A 100 '"env_file"' "$backup_file" | grep '"content"' | sed 's/.*"content":"\([^"]*\)".*/\1/' | head -1)
            if [ -n "$env_content" ]; then
                echo "$env_content" | base64 -d > .env 2>/dev/null || echo "$env_content" | base64 -D > .env 2>/dev/null
                restore_count=$((restore_count + 1))
            fi
        fi
        
        dialog --stdout --msgbox "Basic restore completed.\n\nRestored $restore_count file(s).\n\nNote: Install 'jq' for full restore functionality." 10 60 2>&1 >/dev/null
    fi
}

# ============================================================================
# STATUS BAR FUNCTIONS
# ============================================================================

# Function to get color block for status (GREEN=good, YELLOW=warning, RED=failure)
get_status_color_block() {
    local status=$1
    case "$status" in
        "healthy"|"good"|"running"|"✓")
            echo "${GREEN}█${NC}"
            ;;
        "warning"|"unhealthy"|"starting"|"⚠"|"⟳"|"?"|"⚠")
            echo "${YELLOW}█${NC}"
            ;;
        "failure"|"exited"|"stopped"|"not_found"|"✗")
            echo "${RED}█${NC}"
            ;;
        *)
            echo "${YELLOW}█${NC}"
            ;;
    esac
}

# Function to quickly check MySQL connection status (non-blocking, fast)
check_mysql_status_quick() {
    # Check if .env exists
    if [ ! -f .env ]; then
        echo "unknown"
        return
    fi
    
    # Load MySQL credentials
    local mysql_host
    local mysql_user
    local mysql_pass
    
    mysql_host=$(read_env_value "MYSQL_HOST")
    mysql_user=$(read_env_value "MYSQL_MOAD_RO_USER")
    mysql_pass=$(read_env_value "MYSQL_MOAD_RO_PASSWORD")
    
    # Check if credentials are set
    if [ -z "$mysql_host" ] || [ -z "$mysql_user" ] || [ -z "$mysql_pass" ]; then
        echo "unknown"
        return
    fi
    
    # Quick TCP connection test (timeout 1 second, non-blocking)
    if timeout 1 bash -c "exec 3<>/dev/tcp/$mysql_host/3306" 2>/dev/null; then
        exec 3<&-
        exec 3>&-
        echo "healthy"
    else
        echo "failure"
    fi
}

# Function to check NFS mount status
check_nfs_mount_status() {
    local mount_path="/data/moad/logs"
    
    # Check if path exists
    if [ ! -d "$mount_path" ]; then
        echo "failure"
        return
    fi
    
    # Check if path is readable
    if [ ! -r "$mount_path" ]; then
        echo "failure"
        return
    fi
    
    # Check if it's a mount point
    if mountpoint -q "$mount_path" 2>/dev/null; then
        # Check if it's NFS (preferred) or another remote filesystem
        if mount | grep -qE "$mount_path.*(nfs|nfs4)"; then
            echo "healthy"
        else
            # Mounted but not NFS - still OK (could be CIFS, etc.)
            echo "healthy"
        fi
    else
        # Not a mount point - might be local directory (OK for development)
        # Check if expected log directories exist
        if [ -d "$mount_path/app1" ] || [ -d "$mount_path/app2" ]; then
            echo "warning"
        else
            echo "failure"
        fi
    fi
}

# Function to get Vector structured files statistics
get_vector_files_stats() {
    local vector_dir="./data/vector/structured"
    local record_count=0
    local latest_timestamp=""
    local latest_file=""
    local latest_file_time=0
    
    # Check if directory exists
    if [ ! -d "$vector_dir" ]; then
        echo "0|"
        return
    fi
    
    # Find all vector files (both .jsonl and .jsonl.gz)
    local files
    files=$(find "$vector_dir" -name "vector-*.jsonl*" -type f 2>/dev/null | sort)
    
    if [ -z "$files" ]; then
        echo "0|"
        return
    fi
    
    # Process each file to count records and find latest timestamp
    while IFS= read -r file; do
        if [ -z "$file" ]; then
            continue
        fi
        
        # Count records (lines) in file
        local file_records=0
        if [[ "$file" == *.gz ]]; then
            # Compressed file
            file_records=$(gunzip -c "$file" 2>/dev/null | wc -l | tr -d ' ')
        else
            # Uncompressed file
            file_records=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
        fi
        
        if [ -n "$file_records" ] && [ "$file_records" -gt 0 ]; then
            record_count=$((record_count + file_records))
            
            # Get the latest timestamp from this file (check last few lines for most recent)
            local file_latest=""
            local last_lines=""
            
            if [[ "$file" == *.gz ]]; then
                # Compressed file - get last 10 lines
                last_lines=$(gunzip -c "$file" 2>/dev/null | tail -10)
            else
                # Uncompressed file
                last_lines=$(tail -10 "$file" 2>/dev/null)
            fi
            
            # Extract timestamp from JSON lines (try @timestamp first, then timestamp)
            if [ -n "$last_lines" ]; then
                # Try using jq if available (more reliable)
                if command -v jq >/dev/null 2>&1; then
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                            local ts
                            ts=$(echo "$line" | jq -r '.@timestamp // .timestamp // empty' 2>/dev/null)
                            if [ -n "$ts" ] && [ "$ts" != "null" ]; then
                                file_latest="$ts"
                            fi
                        fi
                    done <<< "$last_lines"
                else
                    # Fallback: use grep/sed to extract timestamp
                    file_latest=$(echo "$last_lines" | grep -oE '"@timestamp":"[^"]*"|"timestamp":"[^"]*"' | tail -1 | sed 's/.*"\([^"]*\)".*/\1/')
                fi
            fi
            
            # If we found a timestamp, check if it's newer
            if [ -n "$file_latest" ] && [ "$file_latest" != "null" ]; then
                # Convert timestamp to epoch for comparison (handle ISO 8601 format)
                local file_epoch=0
                if command -v date >/dev/null 2>&1; then
                    # Try ISO 8601 format first
                    file_epoch=$(date -d "$file_latest" +%s 2>/dev/null || echo "0")
                    # If that failed, try other formats
                    if [ "$file_epoch" = "0" ]; then
                        file_epoch=$(date -d "$(echo "$file_latest" | sed 's/T/ /' | cut -d'.' -f1)" +%s 2>/dev/null || echo "0")
                    fi
                fi
                
                if [ "$file_epoch" -gt "$latest_file_time" ] && [ "$file_epoch" != "0" ]; then
                    latest_file_time=$file_epoch
                    latest_timestamp="$file_latest"
                    latest_file="$file"
                fi
            fi
        fi
    done <<< "$files"
    
    # Format latest timestamp for display (compact format)
    local display_timestamp=""
    if [ -n "$latest_timestamp" ] && [ "$latest_file_time" -gt 0 ]; then
        # Convert epoch to readable format (YYYY-MM-DD HH:MM)
        if command -v date >/dev/null 2>&1; then
            display_timestamp=$(date -d "@$latest_file_time" "+%Y-%m-%d %H:%M" 2>/dev/null || \
                               date -r "$latest_file_time" "+%Y-%m-%d %H:%M" 2>/dev/null || \
                               echo "")
        fi
        # Fallback: use original timestamp if date conversion failed
        if [ -z "$display_timestamp" ]; then
            display_timestamp=$(echo "$latest_timestamp" | sed 's/T/ /' | cut -d'.' -f1 | cut -d'+' -f1 | cut -d'Z' -f1 | cut -d' ' -f1,2 | cut -c1-16)
        fi
    fi
    
    # Return: record_count|latest_timestamp
    echo "${record_count}|${display_timestamp}"
}

# Function to get container health status
get_container_health() {
    local container=$1
    local health
    
    # Check if container exists
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "not_found"
        return
    fi
    
    # Get health status (if healthcheck is configured)
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    
    # If no healthcheck, check if container is running
    if [ "$health" = "none" ] || [ -z "$health" ]; then
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        if [ "$status" = "running" ]; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "$health"
    fi
}

# Function to get container status summary
get_container_status() {
    local container=$1
    local status
    
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "not_found"
        return
    fi
    
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
    echo "$status"
}

# Function to generate status bar
generate_status_bar() {
    local containers=("moad-vector" "moad-loki" "moad-prometheus" "moad-mysqld-exporter" "moad-grafana")
    local status_items=()
    local overall_health="healthy"
    
    # Build status items array with color blocks
    for container in "${containers[@]}"; do
        local status
        local health
        local display_name
        local status_value
        
        # Always get fresh status from docker
        status=$(get_container_status_from_docker "$container")
        health=$(get_container_health "$container")
        
        # Get short name (remove moad- prefix)
        display_name=$(echo "$container" | sed 's/^moad-//')
        
        # Determine health status value
        if [ "$status" = "not_found" ] || [ "$status" = "exited" ] || [ "$status" = "stopped" ]; then
            status_value="failure"
            overall_health="failure"
        elif [ "$health" = "healthy" ] || ([ "$health" = "running" ] && [ "$status" = "running" ]); then
            status_value="healthy"
        elif [ "$health" = "unhealthy" ]; then
            status_value="warning"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
        elif [ "$health" = "starting" ]; then
            status_value="warning"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
        else
            status_value="warning"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
        fi
        
        # Add to status items: "color_block name"
        local color_block
        color_block=$(get_status_color_block "$status_value")
        status_items+=("${color_block}${display_name}")
    done
    
    # Check MySQL connection status
    local mysql_status
    mysql_status=$(check_mysql_status_quick)
    local mysql_color_block
    mysql_color_block=$(get_status_color_block "$mysql_status")
    status_items+=("${mysql_color_block}mysql")
    
    # Update overall health based on MySQL
    if [ "$mysql_status" = "failure" ]; then
        if [ "$overall_health" = "healthy" ]; then
            overall_health="warning"
        fi
    fi
    
    # Check NFS mount status
    local nfs_status
    nfs_status=$(check_nfs_mount_status)
    local nfs_color_block
    nfs_color_block=$(get_status_color_block "$nfs_status")
    status_items+=("${nfs_color_block}nfs")
    
    # Update overall health based on NFS
    if [ "$nfs_status" = "failure" ]; then
        if [ "$overall_health" = "healthy" ]; then
            overall_health="warning"
        fi
    elif [ "$nfs_status" = "warning" ]; then
        if [ "$overall_health" = "healthy" ]; then
            overall_health="warning"
        fi
    fi
    
    # Get Vector structured files statistics
    local vector_stats
    vector_stats=$(get_vector_files_stats)
    local vector_record_count
    local vector_latest_time
    vector_record_count=$(echo "$vector_stats" | cut -d'|' -f1)
    vector_latest_time=$(echo "$vector_stats" | cut -d'|' -f2)
    
    # Format vector stats for display
    local vector_display=""
    if [ "$vector_record_count" = "0" ]; then
        vector_display="0r"
    else
        # Format large numbers with K/M suffix
        if [ "$vector_record_count" -gt 1000000 ]; then
            vector_display=$(echo "scale=1; $vector_record_count/1000000" | bc 2>/dev/null | sed 's/\.0$//')
            vector_display="${vector_display}M"
        elif [ "$vector_record_count" -gt 1000 ]; then
            vector_display=$(echo "scale=1; $vector_record_count/1000" | bc 2>/dev/null | sed 's/\.0$//')
            vector_display="${vector_display}K"
        else
            vector_display="$vector_record_count"
        fi
        vector_display="${vector_display}r"
        if [ -n "$vector_latest_time" ]; then
            local compact_time
            compact_time=$(echo "$vector_latest_time" | sed 's/^[0-9]\{4\}-//' | cut -d' ' -f1,2)
            vector_display="${vector_display} ${compact_time}"
        fi
    fi
    status_items+=("${vector_display}")
    
    # Determine overall badge with color block
    local overall_color_block
    overall_color_block=$(get_status_color_block "$overall_health")
    local overall_text=""
    case "$overall_health" in
        "healthy")
            overall_text="HEALTHY"
            ;;
        "warning")
            overall_text="WARNING"
            ;;
        *)
            overall_text="FAILURE"
            ;;
    esac
    local overall_badge="${overall_color_block} ${overall_text}"
    
    # Build status lines (split into 1-2 lines if needed)
    local line1=""
    local line2=""
    local total_items=${#status_items[@]}
    local items_per_line=$(( (total_items + 1) / 2 ))  # Distribute evenly
    
    # First line: overall badge + first half of items
    line1="${overall_badge}"
    for ((i=0; i<items_per_line && i<total_items; i++)); do
        if [ -n "$line1" ]; then
            line1="${line1} | ${status_items[$i]}"
        else
            line1="${status_items[$i]}"
        fi
    done
    
    # Second line: remaining items (if any)
    if [ $total_items -gt $items_per_line ]; then
        for ((i=items_per_line; i<total_items; i++)); do
            if [ -z "$line2" ]; then
                line2="${status_items[$i]}"
            else
                line2="${line2} | ${status_items[$i]}"
            fi
        done
    fi
    
    # Return formatted status bar (1-2 lines)
    if [ -n "$line2" ]; then
        echo -e "${line1}\n${line2}"
    else
        echo "${line1}"
    fi
}

# Function to show status bar in dialog
show_status_bar() {
    local status_bar
    status_bar=$(generate_status_bar)
    
    # Show status bar as a separate dialog box (non-blocking info)
    # We'll integrate this into the menu title instead
    echo "$status_bar"
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
    while true; do
        # Generate status bar (may be 1-2 lines)
        local status_bar
        status_bar=$(generate_status_bar)
        
        # Extract overall health for title color/emphasis (from first line)
        local overall_status
        overall_status=$(echo "$status_bar" | head -1 | sed 's/.*█ //' | cut -d' ' -f1)
        
        # Calculate menu height based on status bar lines
        local status_lines
        status_lines=$(echo "$status_bar" | wc -l | tr -d ' ')
        local menu_height=22
        local adjusted_height=$((menu_height + status_lines))
        
        choice=$(dialog --colors --stdout --title "MOAD Stack Manager" \
            --extra-button --extra-label "Refresh" \
            --menu "$status_bar\n\nSelect an operation:" $adjusted_height 100 0 \
            "1" "\Z4Environment\Zn: Generate .env File" \
            "2" "\Z4Environment\Zn: View .env File" \
            "3" "\Z2Docker\Zn: View Container Status" \
            "4" "\Z2Docker\Zn: Start All Containers" \
            "5" "\Z2Docker\Zn: Create & Start (Build)" \
            "6" "\Z2Docker\Zn: Stop All Containers" \
            "7" "\Z2Docker\Zn: Restart All Containers" \
            "8" "\Z2Docker\Zn: Restart Individual Container" \
            "9" "\Z2Docker\Zn: View Container Logs" \
            "10" "\Z2Docker\Zn: View Recent Errors" \
            "11" "\Z2Docker\Zn: Pull Latest Images" \
            "12" "\Z1Docker\Zn: Complete Prune & Purge (DESTRUCTIVE)" \
            "13" "\Z6Services\Zn: Show Service URLs" \
            "14" "\Z6Services\Zn: Check Service Health" \
            "15" "\Z6Services\Zn: Test MySQL Connectivity" \
            "16" "\Z3System\Zn: View Disk Usage" \
            "17" "\Z3System\Zn: View System Resources" \
            "18" "\Z5Config\Zn: View Configuration Files" \
            "20" "\Z6Backup\Zn: Backup MOAD Configuration" \
            "21" "\Z6Backup\Zn: Restore MOAD Configuration" \
            "19" "Exit MOAD Manager" 2>&1)
        
        # Handle extra button (Refresh) or ESC
        local exit_code=$?
        if [ $exit_code -eq 3 ]; then
            # Refresh button pressed - just loop back to refresh status
            continue
        fi
        
        # ESC or cancel - exit only if explicitly requested
        # The exit option (19) is handled in the case statement below
        if [ $exit_code -ne 0 ]; then
            # User pressed ESC - return to main menu (loop continues)
            continue
        fi
        
        case "$choice" in
            1)
                generate_env_file
                ;;
            2)
                view_env_file
                ;;
            3)
                show_container_status
                ;;
            4)
                start_all_containers
                ;;
            5)
                create_and_start_containers
                ;;
            6)
                stop_all_containers
                ;;
            7)
                restart_all_containers
                ;;
            8)
                restart_individual_container
                ;;
            9)
                view_container_logs
                ;;
            10)
                view_recent_errors
                ;;
            11)
                pull_latest_images
                ;;
            12)
                complete_prune_purge
                ;;
            13)
                show_service_urls
                ;;
            14)
                check_service_health
                ;;
            15)
                test_mysql_connectivity
                ;;
            16)
                show_disk_usage
                ;;
            17)
                show_system_resources
                ;;
            18)
                view_configuration_files
                ;;
            20)
                backup_moad_config
                ;;
            21)
                restore_moad_config
                ;;
            19)
                dialog --stdout --yesno "Exit MOAD Manager?" 6 40 2>&1 >/dev/null
                if [ $? -eq 0 ]; then
                    dialog --stdout --msgbox "Exiting MOAD Manager." 6 40 2>&1 >/dev/null
                    clear
                    exit 0
                fi
                # If user cancels exit confirmation, return to menu
                ;;
            "")
                # Empty choice (shouldn't happen, but handle gracefully)
                continue
                ;;
        esac
    done
}

# Override trap to include lock cleanup
# Trap already set above - this line removed to avoid duplicate

# Start the menu
main_menu

