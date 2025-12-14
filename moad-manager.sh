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

# Function to get MOAD containers
get_moad_containers() {
    docker compose ps --format "{{.Name}}" 2>/dev/null | grep "^moad-" || echo ""
}

# Function to get all containers (running and stopped)
get_all_containers() {
    docker compose ps -a --format "{{.Name}}" 2>/dev/null || echo ""
}

# Function to get running containers
get_running_containers() {
    docker compose ps --format "{{.Name}}" --filter "status=running" 2>/dev/null || echo ""
}

# Function to get stopped containers
get_stopped_containers() {
    docker compose ps --format "{{.Name}}" --filter "status=stopped" 2>/dev/null || echo ""
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
    
    # Display .env file contents without masking (user has root access)
    local env_content
    env_content=$(cat .env)
    
    dialog --stdout --title ".env File Contents" --msgbox "$env_content" 20 70 2>&1 >/dev/null
}

# ============================================================================
# DOCKER OPERATIONS
# ============================================================================

show_container_status() {
    local status_output
    status_output=$(docker compose ps 2>/dev/null || echo "No containers found or docker compose not available")
    
    dialog --stdout --title "MOAD Container Status" --msgbox "$status_output" 20 80 2>&1 >/dev/null
}

stop_all_containers() {
    local running
    running=$(get_running_containers)
    
    if [ -z "$running" ]; then
        dialog --stdout --msgbox "No running containers to stop." 8 50 2>&1 >/dev/null
        return
    fi
    
    dialog --stdout --yesno "Stop all MOAD containers?\n\nRunning containers:\n$running" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local result=1
        {
            echo "XXX"
            echo "0"
            echo "Stopping containers..."
            echo "XXX"
            sleep 1
            
            echo "XXX"
            echo "50"
            echo "Stopping containers..."
            echo "XXX"
            
            docker compose stop >/dev/null 2>&1
            result=$?
            
            if [ $result -eq 0 ]; then
                echo "XXX"
                echo "100"
                echo "✓ All containers stopped successfully!"
                echo "XXX"
            else
                echo "XXX"
                echo "100"
                echo "✗ Failed to stop containers"
                echo "XXX"
            fi
            sleep 1
        } | dialog --colors --gauge "Stopping containers..." 8 60 0
        
        if [ $result -eq 0 ]; then
            dialog --stdout --msgbox "All containers stopped successfully." 8 50 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Error: Failed to stop containers." 8 50 2>&1 >/dev/null
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
                
                docker compose up -d >/dev/null 2>&1
                result=$?
                
                if [ $result -eq 0 ]; then
                    echo "XXX"
                    echo "100"
                    echo "✓ All containers created and started successfully!"
                    echo "XXX"
                else
                    echo "XXX"
                    echo "100"
                    echo "✗ Failed to create/start containers"
                    echo "XXX"
                fi
                sleep 1
            } | dialog --colors --gauge "Creating and starting containers..." 8 60 0
            
            if [ $result -eq 0 ]; then
                dialog --stdout --msgbox "All containers created and started successfully." 8 50 2>&1 >/dev/null
            else
                dialog --stdout --msgbox "Error: Failed to create/start containers.\n\nCheck logs for details." 10 50 2>&1 >/dev/null
            fi
        fi
        return
    fi
    
    # If containers exist but none are stopped
    if [ -z "$stopped" ]; then
        dialog --stdout --msgbox "All containers are already running." 8 50 2>&1 >/dev/null
        return
    fi
    
    # Start stopped containers
    dialog --stdout --yesno "Start all stopped MOAD containers?\n\nStopped containers:\n$stopped" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local result=1
        {
            echo "XXX"
            echo "0"
            echo "Starting containers..."
            echo "XXX"
            sleep 1
            
            echo "XXX"
            echo "50"
            echo "Starting containers..."
            echo "XXX"
            
            docker compose start >/dev/null 2>&1
            result=$?
            
            if [ $result -eq 0 ]; then
                echo "XXX"
                echo "100"
                echo "✓ All containers started successfully!"
                echo "XXX"
            else
                echo "XXX"
                echo "100"
                echo "✗ Failed to start containers"
                echo "XXX"
            fi
            sleep 1
        } | dialog --colors --gauge "Starting containers..." 8 60 0
        
        if [ $result -eq 0 ]; then
            dialog --stdout --msgbox "All containers started successfully." 8 50 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Error: Failed to start containers." 8 50 2>&1 >/dev/null
        fi
    fi
}

# Function to create and start containers (build if needed)
create_and_start_containers() {
    local all_containers
    all_containers=$(get_all_containers)
    
    if [ -n "$all_containers" ]; then
        dialog --stdout --yesno "Containers already exist. Recreate and start all MOAD containers?\n\nThis will recreate:\n$all_containers\n\nExisting containers will be stopped and recreated." 14 60 2>&1 >/dev/null
        if [ $? -ne 0 ]; then
            return
        fi
    fi
    
    dialog --stdout --yesno "Create and start all MOAD containers?\n\nThis will:\n- Create containers from images\n- Start all services\n- Build if needed" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local result=1
        {
            echo "XXX"
            echo "0"
            echo "Building images (if needed)..."
            echo "XXX"
            sleep 1
            
            echo "XXX"
            echo "30"
            echo "Creating containers..."
            echo "XXX"
            sleep 1
            
            echo "XXX"
            echo "60"
            echo "Starting containers..."
            echo "XXX"
            
            docker compose up -d --build >/dev/null 2>&1
            result=$?
            
            if [ $result -eq 0 ]; then
                echo "XXX"
                echo "100"
                echo "✓ All containers created and started successfully!"
                echo "XXX"
            else
                echo "XXX"
                echo "100"
                echo "✗ Failed to create/start containers"
                echo "XXX"
            fi
            sleep 1
        } | dialog --colors --gauge "Creating and starting containers..." 8 60 0
        
        if [ $result -eq 0 ]; then
            dialog --stdout --msgbox "All containers created and started successfully." 8 50 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Error: Failed to create/start containers.\n\nCheck logs for details." 10 50 2>&1 >/dev/null
        fi
    fi
}

restart_all_containers() {
    local all_containers
    all_containers=$(get_all_containers)
    
    if [ -z "$all_containers" ]; then
        dialog --stdout --msgbox "No containers found." 8 50 2>&1 >/dev/null
        return
    fi
    
    dialog --stdout --yesno "Restart all MOAD containers?\n\nContainers:\n$all_containers" 12 60 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        local result=1
        {
            echo "XXX"
            echo "0"
            echo "Stopping containers..."
            echo "XXX"
            sleep 1
            
            echo "XXX"
            echo "50"
            echo "Starting containers..."
            echo "XXX"
            
            docker compose restart >/dev/null 2>&1
            result=$?
            
            if [ $result -eq 0 ]; then
                echo "XXX"
                echo "100"
                echo "✓ All containers restarted successfully!"
                echo "XXX"
            else
                echo "XXX"
                echo "100"
                echo "✗ Failed to restart containers"
                echo "XXX"
            fi
            sleep 1
        } | dialog --colors --gauge "Restarting containers..." 8 60 0
        
        if [ $result -eq 0 ]; then
            dialog --stdout --msgbox "All containers restarted successfully." 8 50 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Error: Failed to restart containers." 8 50 2>&1 >/dev/null
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
        if docker compose restart "$selected" >/dev/null 2>&1; then
            dialog --stdout --msgbox "Container $selected restarted successfully." 8 50 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "Error: Failed to restart $selected." 8 50 2>&1 >/dev/null
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
    logs=$(docker compose logs --tail="$lines" "$selected" 2>&1)
    
    if [ -z "$logs" ]; then
        logs="No logs available for $selected"
    fi
    
    dialog --stdout --title "Logs: $selected" --msgbox "$logs" 25 80 2>&1 >/dev/null
}

view_recent_errors() {
    local containers
    local menu_items=()
    local all_errors=""
    
    containers=$(get_all_containers)
    
    if [ -z "$containers" ]; then
        dialog --stdout --msgbox "No containers found." 8 50 2>&1 >/dev/null
        return
    fi
    
    dialog --stdout --infobox "Scanning logs for errors..." 5 50 2>&1 >/dev/null
    
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            local errors
            errors=$(docker compose logs --tail=50 "$container" 2>&1 | grep -i "error\|fatal\|exception\|failed" | head -10)
            if [ -n "$errors" ]; then
                all_errors+="\n=== $container ===\n$errors\n"
            fi
        fi
    done <<< "$containers"
    
    if [ -z "$all_errors" ]; then
        all_errors="No recent errors found in container logs."
    fi
    
    dialog --stdout --title "Recent Errors in Logs" --msgbox "$all_errors" 25 80 2>&1 >/dev/null
}

pull_latest_images() {
    dialog --stdout --yesno "Pull latest images for all MOAD services?" 8 50 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        return
    fi
    
    local images=("timberio/vector:0.38.0-alpine" "grafana/loki:2.9.0" "prom/prometheus:v2.48.0" "prom/mysqld-exporter:v0.15.1" "grafana/grafana:12.3.0")
    local image_names=("vector" "loki" "prometheus" "mysqld-exporter" "grafana")
    local total=${#images[@]}
    local current=0
    
    # Create progress display
    {
        for i in "${!images[@]}"; do
            current=$((i + 1))
            local percent=$((current * 100 / total))
            local image_name="${image_names[$i]}"
            
            echo "XXX"
            echo "$percent"
            echo "Pulling image $current/$total: $image_name..."
            echo "XXX"
            
            # Pull the image and capture output
            docker pull "${images[$i]}" >/dev/null 2>&1
            local pull_status=$?
            
            if [ $pull_status -eq 0 ]; then
                echo "XXX"
                echo "$percent"
                echo "✓ $image_name: Pulled successfully"
                echo "XXX"
            else
                echo "XXX"
                echo "$percent"
                echo "✗ $image_name: Pull failed"
                echo "XXX"
            fi
            
            sleep 0.5
        done
        
        echo "XXX"
        echo "100"
        echo "All images pulled successfully!"
        echo "XXX"
        sleep 1
    } | dialog --colors --gauge "Pulling latest images..." 10 70 0
    
    dialog --stdout --msgbox "Image pull completed." 8 50 2>&1 >/dev/null
}

complete_prune_purge() {
    dialog --stdout --yesno "WARNING: This will:\n\n- Stop all MOAD containers\n- Remove all containers\n- Remove all volumes\n- Remove all networks\n- Prune all unused Docker resources\n\nThis is DESTRUCTIVE and cannot be undone!\n\nContinue?" 15 70 2>&1 >/dev/null
    
    if [ $? -eq 0 ]; then
        dialog --stdout --infobox "Performing complete Docker cleanup..." 5 50 2>&1 >/dev/null
        
        # Stop MOAD containers
        docker compose down >/dev/null 2>&1 || true
        
        # Remove all containers
        docker container prune -f >/dev/null 2>&1 || true
        
        # Remove all volumes
        docker volume prune -f >/dev/null 2>&1 || true
        
        # Remove all networks (except defaults)
        docker network prune -f >/dev/null 2>&1 || true
        
        # Complete system prune
        docker system prune -af --volumes >/dev/null 2>&1 || true
        
        dialog --stdout --msgbox "Complete Docker cleanup finished.\n\nAll containers, volumes, and networks have been removed." 10 60 2>&1 >/dev/null
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
    info+="  URL: ${PROMETHEUS_URL}\n"
    info+="\n"
    info+="Loki (Logs):\n"
    info+="  URL: ${LOKI_URL}\n"
    info+="\n"
    info+="MySQL Exporter:\n"
    info+="  Port: 9104\n"
    info+="  Metrics: ${PROMETHEUS_URL}/targets\n"
    
    dialog --stdout --title "Service URLs" --msgbox "$info" 18 70 2>&1 >/dev/null
}

check_service_health() {
    local health_info="Service Health Check:\n\n"
    local all_healthy=true
    
    # Check Grafana
    dialog --stdout --infobox "Checking services..." 5 50 2>&1 >/dev/null
    
    if curl -s -f "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
        health_info+="✓ Grafana: Healthy\n"
    else
        health_info+="✗ Grafana: Unreachable\n"
        all_healthy=false
    fi
    
    # Check Prometheus
    if curl -s -f "${PROMETHEUS_URL}/-/healthy" >/dev/null 2>&1; then
        health_info+="✓ Prometheus: Healthy\n"
    else
        health_info+="✗ Prometheus: Unreachable\n"
        all_healthy=false
    fi
    
    # Check Loki
    if curl -s -f "${LOKI_URL}/ready" >/dev/null 2>&1; then
        health_info+="✓ Loki: Healthy\n"
    else
        health_info+="✗ Loki: Unreachable\n"
        all_healthy=false
    fi
    
    # Check MySQL Exporter
    if curl -s -f "http://localhost:9104/metrics" >/dev/null 2>&1; then
        health_info+="✓ MySQL Exporter: Healthy\n"
    else
        health_info+="✗ MySQL Exporter: Unreachable\n"
        all_healthy=false
    fi
    
    # Check Vector
    if docker ps --format "{{.Names}}" | grep -q "^moad-vector$"; then
        health_info+="✓ Vector: Running\n"
    else
        health_info+="✗ Vector: Not Running\n"
        all_healthy=false
    fi
    
    health_info+="\n"
    if [ "$all_healthy" = true ]; then
        health_info+="Overall Status: All services healthy ✓"
    else
        health_info+="Overall Status: Some services unhealthy ✗"
    fi
    
    dialog --stdout --title "Service Health" --msgbox "$health_info" 15 60 2>&1 >/dev/null
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
        dialog --stdout --msgbox "MySQL Connection: SUCCESS\n\nHost: $mysql_host\nUser: $mysql_user\n\nConnection test passed." 10 60 2>&1 >/dev/null
    else
        dialog --stdout --msgbox "MySQL Connection: FAILED\n\nError details:\n$result\n\nPlease check:\n- MySQL host is correct\n- User credentials are correct\n- Network connectivity" 15 70 2>&1 >/dev/null
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
    
    dialog --stdout --title "Disk Usage" --msgbox "$info" 15 70 2>&1 >/dev/null
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
    
    dialog --stdout --title "System Resources" --msgbox "$info" 10 60 2>&1 >/dev/null
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
    )
    
    local selected
    local exit_code
    selected=$(dialog --stdout --title "View Configuration" \
        --menu "Select a configuration file to view:" 12 60 5 \
        "${menu_items[@]}" 2>&1)
    exit_code=$?
    
    # Handle cancel/ESC - return to main menu
    if [ $exit_code -ne 0 ] || [ -z "$selected" ]; then
        return
    fi
    
    if [ -f "$selected" ]; then
        local content
        content=$(head -100 "$selected" 2>/dev/null || echo "Error reading file")
        dialog --stdout --title "Config: $selected" --msgbox "$content" 25 80 2>&1 >/dev/null
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
    local status_line=""
    local overall_health="healthy"
    local healthy_count=0
    local warning_count=0
    local failure_count=0
    local total_count=0
    
    for container in "${containers[@]}"; do
        local status
        local health
        local display_name
        
        status=$(get_container_status "$container")
        health=$(get_container_health "$container")
        
        # Get short name (remove moad- prefix)
        display_name=$(echo "$container" | sed 's/^moad-//')
        
        # Determine health badge
        local badge=""
        if [ "$status" = "not_found" ] || [ "$status" = "exited" ] || [ "$status" = "stopped" ]; then
            badge="✗"
            overall_health="failure"
            failure_count=$((failure_count + 1))
        elif [ "$health" = "healthy" ] || ([ "$health" = "running" ] && [ "$status" = "running" ]); then
            badge="✓"
            healthy_count=$((healthy_count + 1))
        elif [ "$health" = "unhealthy" ]; then
            badge="⚠"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
            warning_count=$((warning_count + 1))
        elif [ "$health" = "starting" ]; then
            badge="⟳"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
            warning_count=$((warning_count + 1))
        else
            badge="?"
            if [ "$overall_health" = "healthy" ]; then
                overall_health="warning"
            fi
            warning_count=$((warning_count + 1))
        fi
        
        # Build status line (format: badge name)
        if [ -z "$status_line" ]; then
            status_line="${badge}${display_name}"
        else
            status_line="${status_line} | ${badge}${display_name}"
        fi
        
        total_count=$((total_count + 1))
    done
    
    # Determine overall badge
    local overall_badge=""
    if [ "$overall_health" = "healthy" ]; then
        overall_badge="✓ HEALTHY"
    elif [ "$overall_health" = "warning" ]; then
        overall_badge="⚠ WARNING"
    else
        overall_badge="✗ FAILURE"
    fi
    
    # Return formatted status bar
    echo "${overall_badge} | ${status_line}"
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
        # Generate status bar
        local status_bar
        status_bar=$(generate_status_bar)
        
        # Extract overall health for title color/emphasis
        local overall_status
        overall_status=$(echo "$status_bar" | cut -d'|' -f1 | xargs)
        
        choice=$(dialog --colors --stdout --title "MOAD Stack Manager" \
            --extra-button --extra-label "Refresh" \
            --menu "$status_bar\n\nSelect an operation:" 27 85 22 \
            "1" "\Z4Environment\Zn: Generate .env File" \
            "2" "\Z4Environment\Zn: View .env File" \
            "3" "\Z2Docker\Zn: View Container Status" \
            "4" "\Z2Docker\Zn: Start All Containers" \
            "5" "\Z2Docker\Zn: Create & Start (Build if needed)" \
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

# Trap Ctrl-C to exit gracefully
trap 'clear; echo "Exiting MOAD Manager..."; exit 0' INT TERM

# Start the menu
main_menu

