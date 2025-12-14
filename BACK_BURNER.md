# MOAD Back Burner - Future Ideas & Features

This document tracks ideas, future features, and potential enhancements for the MOAD stack. Items are listed in no particular order and may be prioritized or implemented based on operational needs.

---

## Azure Subscription Monitoring Integration

**Status:** Future Consideration  
**Priority:** Medium  
**Category:** Infrastructure Monitoring

### Idea
Add appropriate dashboards that poll metrics from the Azure subscription where the MOAD infrastructure resides. This would provide application managers with a full-spectrum view of the entire environment, from cloud tenant level down to individual VMs.

### Scope
- **Infrastructure Components:**
  - `app1` - Conference Manager server
  - `app2` - Permission Form Manager server
  - `sql1` - MySQL database server
  - `dev1` - MOAD observability stack server

### Proposed Dashboards
1. **Azure Tenant Overview**
   - Subscription-level resource utilization
   - Cost tracking and trends
   - Resource health summary

2. **VM-Level Monitoring**
   - CPU, memory, disk I/O per VM
   - Network throughput and latency
   - VM availability and uptime
   - Resource utilization trends

3. **Integrated View**
   - Correlate Azure VM metrics with application metrics
   - Infrastructure performance impact on application performance
   - Capacity planning insights

### Integration Approach
- Use Azure Monitor API or Azure Exporter for Prometheus
- Add Azure datasource to Grafana
- Create dashboards that complement existing:
  - CM (Conference Manager) dashboards
  - PFM (Permission Form Manager) dashboards
  - Tomcat monitoring dashboards
  - HAProxy monitoring dashboards
  - Postfix monitoring dashboards

### Benefits
- Complete observability from cloud infrastructure to application layer
- Better root cause analysis (infrastructure vs. application issues)
- Capacity planning and resource optimization
- Cost visibility and optimization opportunities

### Considerations
- Azure authentication and permissions (Service Principal, Managed Identity)
- API rate limits and data retention
- Additional Prometheus metrics storage requirements
- Network access from MOAD to Azure APIs

---

## Future Ideas

_Add new ideas below this line..._

