# MOAD - Mother Of All Dashboards

A unified observability and analytics platform for SchoolSoft operations, providing a single source of truth across logs, metrics, and relational data.

## Core Mission

- Provide a single source of truth for SchoolSoft operations
- Unify logs, metrics, and relational data into one analytical plane
- Enable security, operational, and business insight
- Support per-district, per-school, per-user, and per-student visibility
- Enable root-cause analysis across application, infrastructure, and data layers

## Architecture

### Components

- **Vector**: Log ingestion, multiline reconstruction, field extraction, event classification, JSON normalization
  - Entrypoint script validates configuration and log paths before starting
- **Loki**: Log aggregation and storage
  - Entrypoint script validates configuration file before starting
- **Prometheus**: Metrics collection
  - Entrypoint script validates configuration file before starting
- **MySQL Exporter**: Database metrics for `schoolsoft` and `permissionMan` databases (critical for correlation)
  - Entrypoint script creates `.my.cnf` from environment variables at runtime
  - Uses `/tmp/.my.cnf` (writable by container's `nobody` user)
- **Grafana**: Visualization and dashboards
  - Entrypoint script validates environment variables and provisioning paths

### Deployment

- **Host**: `dev1.schoolsoft.net`
- **Runtime**: Docker Compose
- **Filesystem Root**: `/data/moad`

### Network Endpoints

- Grafana: `http://dev1.schoolsoft.net:3000`
- Loki: `http://dev1.schoolsoft.net:3100`
- Prometheus: `http://dev1.schoolsoft.net:9090`

## Key Design: Join Compatibility

**All log-derived identifiers are join-compatible with the MySQL schema.**

This means:
- Integer IDs are extracted as integers (not strings)
- String identifiers are normalized (lowercase, trimmed)
- Email addresses match MySQL column formats
- Usernames are normalized to match `users.userName`
- Each event includes join hints (`mysql_joins` array)

See [docs/JOIN_COMPATIBILITY.md](docs/JOIN_COMPATIBILITY.md) for detailed design.

## Applications Monitored

### CM (Conference Manager)
- **Host**: `app1`
- **Components**: Tomcat, HAProxy, Postfix
- **Log Paths**:
  - Tomcat: `/data/moad/logs/app1/usr/share/apache-tomcat-8.5.94/logs/catalina.out`
  - HAProxy: `/data/moad/logs/app1/var/log/haproxy.log`
  - Mail: `/data/moad/logs/app1/var/log/mail.log`

### PFM (Permission Form Manager)
- **Host**: `app2`
- **Components**: Tomcat, HAProxy, Postfix
- **Log Paths**:
  - Tomcat: `/data/moad/logs/app2/usr/share/apache-tomcat-8.5.94/logs/catalina.out`
  - HAProxy: `/data/moad/logs/app2/var/log/haproxy.log`
  - Mail: `/data/moad/logs/app2/var/log/mail.log`

## MySQL Monitoring

MOAD includes comprehensive MySQL observability for both `schoolsoft` and `permissionMan` databases:

- **Performance Monitoring**: InnoDB buffer pool, query latency, lock contention, connection saturation
- **Application Analytics**: Form lifecycle, per-school activity, integration task timing, growth trends
- **Correlation**: Database performance correlated with application logs and user activity

**MySQL User:** Configurable via `MYSQL_MOAD_RO_USER` (default: `moad_ro`, read-only, least privilege)

See [docs/MYSQL_MONITORING.md](docs/MYSQL_MONITORING.md) for detailed documentation.

## Event Taxonomy

### Authentication Events
- **Sources**: Tomcat, HAProxy
- **Identifiers**: `username`, `email`, `user_id`, `client_ip`, `school_id`
- **Join Path**: `users.userName` → `users.id` → `users.schoolId` → `schools.id`

### PowerSchool Integration Events
- **Source**: Tomcat ConsumerManager
- **Identifiers**: `email`, `student_ids[]`, `school_id`
- **Join Path**: `parents.email` → `parents.userId` → `users.id`

### Email Events
- **Source**: Postfix
- **Identifiers**: `recipient_email`, `sender_email`
- **Join Path**: `users.email` → `users.id` → `users.schoolId` → `schools.id`

### HTTP Traffic Events
- **Source**: HAProxy
- **Identifiers**: `school_subdomain`, `school_id`, `client_ip`
- **Join Path**: `schools.subdomain` → `schools.id`

### Form Events (PermissionMan)
- **Source**: Tomcat (PFM, CM)
- **Identifiers**: `form_id`, `user_form_id`, `user_id`, `school_id`, `district_id`, `student_id`
- **Join Path**: `permissionMan.Form.id`, `permissionMan.UserForm.id`, `permissionMan.User.id`, etc.
- **Actions**: distributed, completed, submitted, expired, archived

### Integration Task Events
- **Source**: Tomcat
- **Identifiers**: `integration_task_id`, `integration_type`, `school_id`, `district_id`
- **Join Path**: `permissionMan.FullIntegrationTask.id`, `permissionMan.DeltaIntegrationTask.id`

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Access to `/data/moad/logs` (NFS mount)
- MySQL database accessible for metrics export
- **Required Ubuntu/Debian packages:**
  - `dialog` - For MOAD Manager UI (will prompt to install if missing)
  - `jq` - For JSON processing in backup/restore (will prompt to install if missing)
  - `coreutils` - For base64, numfmt, and other utilities (usually pre-installed)

**Install required packages:**
```bash
sudo apt-get update
sudo apt-get install -y dialog jq
```

### Environment Variables

**Option 1: Use the MOAD Manager (Recommended)**

```bash
./moad-manager.sh
# Select "1. Environment: Generate .env File" from the menu
```

This will:
- Prompt for MySQL configuration (host, user, password)
- Generate secure random 14-character passwords for Grafana and MySQL Grafana user
- Create the `.env` file automatically

**Option 2: Create manually**

Create a `.env` file:

```bash
GRAFANA_ADMIN_PASSWORD=your_secure_password
MYSQL_HOST=192.168.1.100
MYSQL_MOAD_RO_USER=moad_ro
MYSQL_MOAD_RO_PASSWORD=your_moad_ro_password
MYSQL_GRAFANA_PASSWORD=your_grafana_readonly_password
```

**Note:** `MYSQL_HOST` should be the IP address or hostname of your MySQL server. Using an IP address is recommended for reliability in Docker networks.

### Start Services

**Option 1: Use MOAD Manager (Recommended)**
```bash
./moad-manager.sh
# Select "4. Docker: Start All Containers" or "5. Docker: Create & Start"
```

**Option 2: Use docker compose directly**
```bash
docker compose up -d
```

### Access Dashboards

View service URLs and access information in MOAD Manager:
```bash
./moad-manager.sh
# Select "13. Services: Show Service URLs"
```

Or access directly:
- Grafana: http://dev1.schoolsoft.net:3000
  - Default credentials: `admin` / (from `.env`)
- Prometheus: http://dev1.schoolsoft.net:9090
- Loki: http://dev1.schoolsoft.net:3100

## MOAD Manager

The `moad-manager.sh` script provides a comprehensive, user-friendly interface for managing the entire MOAD stack.

### Key Features

**Visual Interface:**
- **Status Bar**: Real-time container health indicators at the top showing overall status (✓ HEALTHY / ⚠ WARNING / ✗ FAILURE) and individual container states
- **Color-Coded Menu**: Organized by function groups for easy navigation
  - 🔵 Blue: Environment management
  - 🟢 Green: Docker operations
  - 🔴 Red: Destructive operations
  - 🔵 Cyan: Service management
  - 🟡 Yellow: System monitoring
  - 🟣 Magenta: Configuration viewing
- **Progress Bars**: Visual feedback for long-running operations (image pulls, container start/stop/restart)

**Environment Management:**
- Generate `.env` file with interactive prompts
- Pre-loads existing values for easy updates
- Generates secure random 14-character passwords
- View `.env` file contents (no password masking - assumes root access)

**Docker Operations:**
- View container status with health indicators
- Start/stop/restart all containers or individual containers
- Create & start containers (with build support) - handles post-prune scenarios
- View container logs (configurable line count)
- View recent errors across all containers
- Pull latest images with per-image progress tracking
- Complete Docker cleanup (prune & purge) with warnings

**Service Management:**
- Show service URLs and access information
- Check service health (tests all endpoints: Grafana, Prometheus, Loki, MySQL Exporter, Vector)
- Test MySQL connectivity with credential validation

**System Monitoring:**
- View disk usage (system + Docker)
- View system resources (CPU, memory, load average)

**Configuration Management:**
- View configuration files (docker-compose.yml, vector.yml, prometheus.yml, loki-config.yml)

**Backup & Restore:**
- **Backup**: Create JSON backup file containing all configuration
  - `.env` file (all passwords and settings)
  - All configuration files
  - Grafana provisioning and dashboard files
  - Backup metadata (version, timestamp, hostname)
- **Restore**: Restore configuration to new server
  - Validates backup file structure
  - Shows backup information before restore
  - Restores all files to original paths
  - Creates directories as needed
- **Migration**: Perfect for moving MOAD to a new server (clone repo, restore backup, start services)

**User Experience:**
- Cancel/ESC always returns to main menu (never drops to shell)
- Only explicit "Exit" option or Ctrl-C exits the program
- Refresh button to update status bar
- All operations provide clear feedback and error messages

### Usage

```bash
./moad-manager.sh
```

The script will:
1. Check for `dialog` package (prompts to install if missing)
2. Display status bar with container health
3. Show color-coded menu of operations
4. Handle all user interactions gracefully

## Configuration Files

- `docker-compose.yml`: Service definitions
- `vector/vector.yml`: Log processing pipeline
- `loki/loki-config.yml`: Log aggregation configuration
- `prometheus/prometheus.yml`: Metrics collection
- `grafana/provisioning/`: Grafana datasources and dashboards
- `data/vector/structured/`: Structured logs output directory (local, git-ignored)

## Entrypoint Scripts

All containers use custom entrypoint scripts for reliability and validation:

- `vector-entrypoint.sh`: Validates Vector config and log directory accessibility
- `loki-entrypoint.sh`: Validates Loki config file exists and is readable
- `prometheus-entrypoint.sh`: Validates Prometheus config file exists and is readable
- `mysqld-exporter-entrypoint.sh`: Creates `.my.cnf` from environment variables at runtime
- `grafana-entrypoint.sh`: Validates environment variables and provisioning paths

These scripts ensure containers fail fast with clear error messages if configuration is invalid.

## Documentation

**Getting Started:**
- [QUICK_START.md](QUICK_START.md): Quick deployment guide
- [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md): Comprehensive deployment checklist
- [CLEANUP.md](CLEANUP.md): Docker cleanup commands

**Technical Documentation:**
- [JOIN_COMPATIBILITY.md](docs/JOIN_COMPATIBILITY.md): Detailed design of join compatibility
- [SCHEMA_MAPPING.md](docs/SCHEMA_MAPPING.md): Complete mapping of log fields to MySQL columns
- [MYSQL_MONITORING.md](docs/MYSQL_MONITORING.md): MySQL performance and application analytics
- [VALIDATION_GUIDE.md](docs/VALIDATION_GUIDE.md): Validation procedures for join compatibility
- [IDENTIFIER_EXTRACTION_REFERENCE.md](docs/IDENTIFIER_EXTRACTION_REFERENCE.md): Identifier extraction patterns reference

**Change History:**
- [CHANGELOG_MYSQL_MONITORING.md](CHANGELOG_MYSQL_MONITORING.md): MySQL monitoring extension changelog

## Backup and Migration

MOAD Manager includes comprehensive backup and restore functionality:

### Backup
- Creates JSON backup file with all configuration
- Includes `.env` file, all config files, and Grafana dashboards
- Base64-encoded file contents in JSON format
- Backup metadata (version, timestamp, hostname)

### Restore
- Validates backup file structure
- Restores all files to original paths
- Works on new server after `git clone` and `git pull`
- Shows backup information before restore

**Usage:**
```bash
./moad-manager.sh
# Select "20. Backup: Backup MOAD Configuration" to create backup
# Select "21. Backup: Restore MOAD Configuration" to restore
```

**⚠️ Security Note**: Backup files contain sensitive information (passwords). Store securely!

## Success Criteria

- ✅ Any auth failure is visible within 30 seconds
- ✅ All events are attributable to school and app
- ✅ Database stress is explainable via application behavior
- ✅ PowerSchool integrations are fully traceable
- ✅ MOAD becomes the authoritative operational view

## Non-Goals

- ❌ No modification of SchoolSoft source code
- ❌ No inline DB queries from Grafana (metrics only)
- ❌ No duplication of raw logs

## License

Internal SchoolSoft project.
