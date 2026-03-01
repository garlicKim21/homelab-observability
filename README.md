# Homelab Observability

홈랩 인프라 통합 모니터링 스택. ESXi 호스트, VM, 방화벽, NAS, 스위치, AP, 클라우드까지 단일 Grafana로 관측.

## Architecture

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────┐
│  Exporters  │───▶│ VictoriaMetrics  │◀───│   vmalert   │
│             │    │     (TSDB)       │    │  (alerting) │
└─────────────┘    └───────┬──────────┘    └──────┬──────┘
                           │                      │
┌─────────────┐    ┌───────▼──────────┐    ┌──────▼──────┐
│  Promtail   │───▶│     Grafana      │    │Alertmanager │
│  (syslog)   │    │  (dashboards)    │    │  (Discord)  │
└─────────────┘    └──────────────────┘    └─────────────┘
       ▲
┌──────┴──────┐
│    Loki     │
│   (logs)    │
└─────────────┘
```

## Tech Stack

| Component | Role | Version |
|-----------|------|---------|
| [VictoriaMetrics](https://victoriametrics.com/) | Time-series DB (Prometheus compatible) | v1.106.1 |
| [Grafana](https://grafana.com/) | Visualization | v11.4.0 |
| [Loki](https://grafana.com/oss/loki/) | Log aggregation | v3.3.2 |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Syslog receiver | v3.3.2 |
| [vmalert](https://docs.victoriametrics.com/vmalert/) | Alert rule evaluation | v1.106.1 |
| [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) | Alert routing (Discord) | v0.27.0 |
| Docker Compose | Orchestration | - |

## Dashboards

10개 대시보드가 Grafana provisioning으로 자동 로드됩니다.

| Dashboard | Description |
|-----------|-------------|
| Overview | 전체 인프라 요약 |
| ESXi Hosts | ESXi 호스트 CPU, 메모리, 네트워크, 데이터스토어 |
| Virtual Machines | VM별 리소스 사용량 |
| OPNsense Firewall | 방화벽 트래픽, 게이트웨이, DNS |
| Synology NAS | 디스크, 볼륨, 네트워크, 온도 |
| TP-Link Switch | 포트별 트래픽, VLAN |
| ipTime AP | 무선 클라이언트, 트래픽 |
| Logs Explorer | Loki 로그 검색 |
| OCI Cloud | Oracle Cloud 인스턴스 |
| Observer Server | 모니터링 서버 자체 상태 |

## Exporters

| Exporter | Target |
|----------|--------|
| [vmware_exporter](https://github.com/pryorda/vmware_exporter) | vCenter API → ESXi/VM metrics |
| [snmp_exporter](https://github.com/prometheus/snmp_exporter) | SNMP v3 → Switch, NAS, AP |
| [opnsense-exporter](https://github.com/AthennaMind/opnsense-exporter) | OPNsense REST API |
| [blackbox_exporter](https://github.com/prometheus/blackbox_exporter) | HTTP/HTTPS endpoint probing |
| [node_exporter](https://github.com/prometheus/node_exporter) | Linux host metrics |

## Project Structure

```
docker-compose.yml              # All services
.env.example                    # Required environment variables
configs/
  victoriametrics/scrape.yml    # Scrape targets
  grafana/provisioning/         # Datasources + dashboards
  vmalert/alerts/               # Alert rules (7 rule files)
  alertmanager/alertmanager.yml # Alert routing
  loki/loki-config.yml          # Log storage
  promtail/promtail-config.yml  # Syslog receiver
  snmp_exporter/                # SNMP v3 config (gitignored)
  blackbox/blackbox.yml         # HTTP probe targets
docs/                           # Deployment & dashboard guides
```

## Quick Start

```bash
# 1. Clone
git clone https://github.com/garlicKim21/homelab-observability.git
cd homelab-observability

# 2. Configure environment
cp .env.example .env
vi .env  # Fill in your values

# 3. Configure SNMP (if needed)
# Create configs/snmp_exporter/snmp.yml with your SNMP v3 credentials

# 4. Start
docker compose up -d

# 5. Access Grafana
open http://localhost:3000
```

## Alert Rules

| Rule File | Targets |
|-----------|---------|
| `esxi.rules.yml` | ESXi host health, CPU, memory, datastore |
| `nas.rules.yml` | NAS disk, volume, temperature |
| `network.rules.yml` | Switch port, AP connectivity |
| `opnsense.rules.yml` | Firewall, gateway, DNS |
| `oci.rules.yml` | OCI instance health |
| `observer.rules.yml` | Monitoring server self-health |
| `self-monitoring.rules.yml` | Stack component health |

## License

MIT
