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
- **Loki**: Log aggregation and storage
- **Prometheus**: Metrics collection
- **MySQL Exporter**: Database metrics for `schoolsoft` and `permissionMan` databases (critical for correlation)
- **Grafana**: Visualization and dashboards

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

**MySQL User:** `moad_ro` (read-only, least privilege)

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

### Environment Variables

Create a `.env` file:

```bash
GRAFANA_ADMIN_PASSWORD=your_secure_password
MYSQL_MOAD_RO_PASSWORD=your_moad_ro_password
MYSQL_GRAFANA_PASSWORD=your_grafana_readonly_password
```

### Configure MySQL Host Alias

Add `mysql-host` as an alias in your Docker host's `/etc/hosts` file:

```bash
# Edit /etc/hosts (requires sudo)
sudo nano /etc/hosts

# Add a line like this (replace with your actual MySQL hostname or IP):
# 192.168.1.100  mysql-host
# OR if using a hostname:
# mysql-server.example.com  mysql-host
```

**Note:** The `docker-compose.yml` uses `mysql-host` as the hostname. By adding it to `/etc/hosts`, Docker containers will resolve it to your actual MySQL server without needing to edit the compose file.

### Start Services

```bash
docker compose up -d
```

### Access Dashboards

- Grafana: http://dev1.schoolsoft.net:3000
  - Default credentials: `admin` / (from `.env`)
- Prometheus: http://dev1.schoolsoft.net:9090
- Loki: http://dev1.schoolsoft.net:3100

## Configuration Files

- `docker-compose.yml`: Service definitions
- `vector/vector.yml`: Log processing pipeline
- `loki/loki-config.yml`: Log aggregation configuration
- `prometheus/prometheus.yml`: Metrics collection
- `grafana/provisioning/`: Grafana datasources and dashboards
- `data/vector/structured/`: Structured logs output directory (local, git-ignored)

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
