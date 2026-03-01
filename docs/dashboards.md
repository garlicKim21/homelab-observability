# Dashboards Guide

## 대시보드 목록

| # | 파일명 | UID | 제목 | 설명 |
|---|--------|-----|------|------|
| 01 | `01-overview.json` | `homelab-overview` | Overview | 전체 인프라 요약 (ESXi, VM, 네트워크, 스토리지) |
| 02 | `02-esxi-hosts.json` | `esxi-hosts` | ESXi Hosts | ESXi 6대 호스트 CPU, 메모리, 네트워크, 데이터스토어 |
| 03 | `03-vms.json` | `vms-detail` | Virtual Machines | VM별 리소스 사용량 상세 |
| 04 | `04-opnsense.json` | `opnsense-firewall` | OPNsense Firewall | 방화벽 트래픽, 게이트웨이, DNS |
| 05 | `05-nas.json` | `synology-nas` | Synology NAS | NAS 디스크, 볼륨, 네트워크, 온도 |
| 06 | `06-switch.json` | `sg2218-switch` | TP-Link SG2218 Switch | 스위치 포트별 트래픽, VLAN |
| 07 | `07-ap.json` | `iptime-ap` | ipTime AP | AP 무선 클라이언트, 트래픽 |
| 08 | `08-logs.json` | `logs-explorer` | Logs Explorer | Loki 로그 검색 (OPNsense, ESXi, NAS) |
| 09 | `09-oci.json` | `oci-cloud` | OCI Cloud (ratatosk.io) | Oracle Cloud 인스턴스 모니터링 |
| 10 | `10-observer.json` | `observer` | Observer Server | 모니터링 VM 자체 상태 |

## 대시보드 파일 경로

```
configs/grafana/provisioning/dashboards/json/
```

Grafana provisioning을 통해 자동 로드됨 (`dashboards.yml` 설정).

## 대시보드 수정 워크플로우

1. **로컬에서 JSON 편집**
   ```bash
   vi configs/grafana/provisioning/dashboards/json/01-overview.json
   ```

2. **rsync로 서버 배포**
   ```bash
   rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
     configs/grafana/provisioning/dashboards/json/ \
     <user>@<MONITORING_VM_IP>:~/basphere-observability/configs/grafana/provisioning/dashboards/json/
   ```

3. **Grafana 재시작**
   ```bash
   ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP> \
     "cd ~/basphere-observability && docker compose restart grafana"
   ```

4. **브라우저에서 확인**
   - `https://grafana.basphere.dev/d/<UID>` 접속하여 변경사항 확인

## 데이터소스 / Job 이름 매핑

| 데이터소스 | Job 이름 | Exporter | 용도 |
|-----------|---------|----------|------|
| VictoriaMetrics | `vmware` | vmware_exporter (:9272) | ESXi/VM 메트릭 |
| VictoriaMetrics | `snmp_switch` | snmp_exporter (:9116) | SG2218 스위치 |
| VictoriaMetrics | `snmp_nas` | snmp_exporter (:9116) | Synology NAS |
| VictoriaMetrics | `snmp_ap` | snmp_exporter (:9116) | ipTime AP |
| VictoriaMetrics | `opnsense` | opnsense-exporter (:8080) | OPNsense 방화벽 |
| VictoriaMetrics | `blackbox` | blackbox_exporter (:9115) | HTTP 프로빙 |
| VictoriaMetrics | `node` | node_exporter (:9100) | Observer 서버 |
| Loki | - | promtail (:1514) | syslog 수신 |

## Grafana 접속 URL

- 기본: `https://grafana.basphere.dev`
- 대시보드 직접 링크: `https://grafana.basphere.dev/d/<UID>`
  - 예: `https://grafana.basphere.dev/d/homelab-overview`
