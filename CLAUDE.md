# Basphere Observability

홈랩 인프라(ESXi 6대, OPNsense, NAS, Switch, AP, OCI) 통합 모니터링 스택.

## Tech Stack

VictoriaMetrics, Grafana 11, Loki, Promtail, vmalert, Alertmanager, Docker Compose

## Deploy Target

```bash
# SSH 접속 (.env의 MONITORING_VM_IP 참조)
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP>

# 전체 배포
rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
  configs/ <user>@<MONITORING_VM_IP>:~/basphere-observability/configs/

# Grafana 재시작
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP> \
  "cd ~/basphere-observability && docker compose restart grafana"
```

## Project Structure

```
configs/
  grafana/provisioning/     # 대시보드 JSON, 데이터소스
  victoriametrics/          # scrape 설정
  vmalert/alerts/           # alert 규칙 (.yml)
  alertmanager/             # 알림 라우팅 (Discord)
  loki/, promtail/          # 로그 수집
  snmp_exporter/, blackbox/ # 네트워크 장비
docker-compose.yml          # 전체 서비스 정의
docs/                       # 상세 문서
data/                       # 런타임 데이터 (gitignore)
```

## Datasources

| Name             | Type       | URL                          |
|------------------|------------|------------------------------|
| VictoriaMetrics  | prometheus | http://victoriametrics:8428  |
| Loki             | loki       | http://loki:3100             |
| Alertmanager     | alertmanager | http://alertmanager:9093   |

## Dashboard Style Guide

대시보드를 새로 만들거나 수정할 때 반드시 [docs/dashboard-style-guide.md](docs/dashboard-style-guide.md)를 따를 것. 패널 제목, textMode, 색상, 장비 식별자 등의 일관성 규칙이 정의되어 있음.

## Docs

- [docs/deployment.md](docs/deployment.md) - 배포 절차 상세
- [docs/dashboards.md](docs/dashboards.md) - 대시보드 목록 및 수정 가이드
- [docs/dashboard-style-guide.md](docs/dashboard-style-guide.md) - 대시보드 UI 스타일 가이드
