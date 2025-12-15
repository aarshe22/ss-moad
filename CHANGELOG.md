# MOAD Changelog

## Version 0.9 (2025-12-15)

### 🎉 Initial Deployment Milestone - STABLE

**Status:** All containers running successfully and stably, MOAD Manager operational, Vector configuration fully validated

### Core Infrastructure
- ✅ All 5 containers running (Vector, Loki, Prometheus, MySQL Exporter, Grafana)
- ✅ Docker Compose V2 orchestration
- ✅ Custom entrypoint scripts for all containers
- ✅ Health checks configured for all services
- ✅ Docker network isolation (only Grafana exposed externally)

### MOAD Manager
- ✅ Comprehensive dialog-based management interface
- ✅ Real-time status bar with container health indicators
- ✅ Environment file generation with secure password generation
- ✅ Docker operations (start, stop, restart, create, pull, prune)
- ✅ Service health monitoring
- ✅ Configuration backup and restore
- ✅ Error logging and troubleshooting tools
- ✅ Lock file mechanism for single instance enforcement

### Log Processing
- ✅ Vector 0.40.0 log ingestion from CM and PFM applications
- ✅ Multiline log reconstruction (compatible regex patterns)
- ✅ Event classification (authentication, forms, integration tasks)
- ✅ Identifier extraction with MySQL join compatibility
- ✅ Structured log output for correlation
- ✅ Loki integration for log aggregation
- ✅ Full VRL validation compliance (all type coercion, error handling, and array operations fixed)

### Metrics Collection
- ✅ Prometheus metrics scraping
- ✅ MySQL Exporter for database metrics
- ✅ Performance schema monitoring
- ✅ Application-level analytics support

### Visualization
- ✅ Grafana dashboards auto-provisioning
- ✅ 4 pre-built dashboards:
  - MySQL Performance
  - PermissionMan Analytics
  - Correlation Dashboard
  - Authentication Failures
- ✅ Loki and Prometheus datasources configured

### Configuration
- ✅ Environment variable management via `.env`
- ✅ MySQL read-only user support (`moad_ro`)
- ✅ NFS log mount support
- ✅ Vector structured logs to local storage

### Documentation
- ✅ Comprehensive README and Quick Start guides
- ✅ Deployment checklist
- ✅ Next steps dashboard guide
- ✅ Technical documentation in `docs/` directory

### Known Working Features
- All containers start and run reliably
- Vector 0.40.0 fully validated and stable (upgraded from 0.38.0)
- All VRL syntax errors resolved (type coercion, error handling, array operations)
- MOAD Manager provides full stack management
- Log ingestion and processing operational
- Metrics collection functional
- Grafana accessible and dashboards loadable

### Technical Improvements (0.9)
- **Vector Upgrade**: Upgraded from 0.38.0 to 0.40.0 for better VRL support
- **VRL Compliance**: Fixed all type coercion issues (string!, to_int with error handling)
- **Array Operations**: Fixed array concatenation with proper error handling
- **Regex Compatibility**: Updated multiline patterns to avoid look-ahead/look-behind
- **Error Handling**: All fallible operations now have explicit error handling

### Next Steps (Post-0.9)
- Dashboard customization and optimization
- Alert rule configuration
- Data validation and join compatibility verification
- Performance tuning
- Additional dashboard creation

