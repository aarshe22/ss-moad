#!/bin/bash
# moad-manager.sh - Comprehensive MOAD stack management interface
# Provides dialog-based interface for all MOAD operations

set -e

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

# Check if dialog is installed
USE_DIALOG=false
if command -v dialog >/dev/null 2>&1; then
    USE_DIALOG=true
else
    echo -e "${YELLOW}Note: 'dialog' not found. This script requires dialog.${NC}"
    echo -e "${BLUE}Please install dialog:${NC}"
    echo ""
    
    # Detect package manager
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${GREEN}sudo apt-get install -y dialog${NC}"
        read -p "Install dialog now? (yes/no) [no]: " install_dialog
        install_dialog=${install_dialog:-no}
        
        if [ "$install_dialog" = "yes" ]; then
            echo "Installing dialog..."
            if sudo apt-get install -y dialog >/dev/null 2>&1; then
                USE_DIALOG=true
                echo -e "${GREEN}Dialog installed successfully!${NC}"
                echo ""
            else
                echo -e "${RED}Failed to install dialog. Exiting.${NC}"
                exit 1
            fi
        else
            echo "Dialog is required for this script. Exiting."
            exit 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        echo -e "  ${GREEN}sudo yum install -y dialog${NC}"
        read -p "Install dialog now? (yes/no) [no]: " install_dialog
        install_dialog=${install_dialog:-no}
        
        if [ "$install_dialog" = "yes" ]; then
            echo "Installing dialog..."
            if sudo yum install -y dialog >/dev/null 2>&1; then
                USE_DIALOG=true
                echo -e "${GREEN}Dialog installed successfully!${NC}"
                echo ""
            else
                echo -e "${RED}Failed to install dialog. Exiting.${NC}"
                exit 1
            fi
        else
            echo "Dialog is required for this script. Exiting."
            exit 1
        fi
    else
        echo -e "${YELLOW}Please install 'dialog' using your system's package manager.${NC}"
        exit 1
    fi
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
        
        if [ $? -ne 0 ]; then
            dialog --stdout --msgbox "Aborted. Existing .env file preserved." 8 50 2>&1 >/dev/null
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
    if [ -n "$existing_mysql_host" ]; then
        mysql_host=$(dialog --stdout --inputbox "MySQL Host (IP address or hostname):" 10 60 "$existing_mysql_host" 2>&1)
    else
        mysql_host=$(dialog --stdout --inputbox "MySQL Host (IP address or hostname):" 10 60 2>&1)
    fi
    
    if [ -z "$mysql_host" ]; then
        dialog --stdout --msgbox "Error: MySQL host is required" 8 50 2>&1 >/dev/null
        return
    fi
    
    # MySQL User
    local mysql_user
    if [ -n "$existing_mysql_user" ]; then
        mysql_user=$(dialog --stdout --inputbox "MySQL User:" 10 60 "$existing_mysql_user" 2>&1)
    else
        mysql_user=$(dialog --stdout --inputbox "MySQL User:" 10 60 "moad_ro" 2>&1)
    fi
    mysql_user=${mysql_user:-moad_ro}
    
    # MySQL Password
    local mysql_password
    if [ -n "$existing_mysql_password" ]; then
        dialog --stdout --yesno "Keep existing MySQL password?" 8 50 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            mysql_password="$existing_mysql_password"
        else
            mysql_password=$(dialog --stdout --passwordbox "Enter new MySQL password:" 10 60 2>&1)
        fi
    else
        mysql_password=$(dialog --stdout --passwordbox "MySQL Password:" 10 60 2>&1)
    fi
    
    if [ -z "$mysql_password" ]; then
        dialog --stdout --msgbox "Error: MySQL password is required" 8 50 2>&1 >/dev/null
        return
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
    
    # Mask passwords in display
    local env_content
    env_content=$(sed 's/\(PASSWORD\)=.*/\1=***MASKED***/g' .env)
    
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
    selected=$(dialog --stdout --title "Select Container to Restart" \
        --menu "Choose a container to restart:" 15 60 10 \
        "${menu_items[@]}" 2>&1)
    
    if [ -n "$selected" ]; then
        dialog --stdout --yesno "Restart container: $selected?" 8 50 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            dialog --stdout --infobox "Restarting $selected..." 5 50 2>&1 >/dev/null
            if docker compose restart "$selected" >/dev/null 2>&1; then
                dialog --stdout --msgbox "Container $selected restarted successfully." 8 50 2>&1 >/dev/null
            else
                dialog --stdout --msgbox "Error: Failed to restart $selected." 8 50 2>&1 >/dev/null
            fi
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
    selected=$(dialog --stdout --title "Select Container for Logs" \
        --menu "Choose a container to view logs:" 15 60 10 \
        "${menu_items[@]}" 2>&1)
    
    if [ -n "$selected" ]; then
        local lines
        lines=$(dialog --stdout --inputbox "Number of log lines to show (default: 100):" 8 50 "100" 2>&1)
        lines=${lines:-100}
        
        dialog --stdout --infobox "Fetching logs for $selected..." 5 50 2>&1 >/dev/null
        local logs
        logs=$(docker compose logs --tail="$lines" "$selected" 2>&1)
        
        if [ -z "$logs" ]; then
            logs="No logs available for $selected"
        fi
        
        dialog --stdout --title "Logs: $selected" --msgbox "$logs" 25 80 2>&1 >/dev/null
    fi
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
    selected=$(dialog --stdout --title "View Configuration" \
        --menu "Select a configuration file to view:" 12 60 5 \
        "${menu_items[@]}" 2>&1)
    
    if [ -n "$selected" ]; then
        if [ -f "$selected" ]; then
            local content
            content=$(head -100 "$selected" 2>/dev/null || echo "Error reading file")
            dialog --stdout --title "Config: $selected" --msgbox "$content" 25 80 2>&1 >/dev/null
        else
            dialog --stdout --msgbox "File not found: $selected" 8 50 2>&1 >/dev/null
        fi
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
            --menu "$status_bar\n\nSelect an operation:" 26 85 20 \
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
            "19" "Exit" 2>&1)
        
        # Handle extra button (Refresh) or ESC
        local exit_code=$?
        if [ $exit_code -eq 3 ]; then
            # Refresh button pressed - just loop back to refresh status
            continue
        fi
        
        if [ $exit_code -ne 0 ]; then
            # ESC or other error
            clear
            exit 0
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
            19|"")
                dialog --stdout --msgbox "Exiting MOAD Manager." 6 40 2>&1 >/dev/null
                clear
                exit 0
                ;;
        esac
    done
}

# Start the menu
main_menu

