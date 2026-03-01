# Deployment Guide

## SSH 접속

```bash
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP>
```

- User: `.env`의 SSH 설정 참조
- Host: `.env`의 `MONITORING_VM_IP` 참조
- Remote path: `~/basphere-observability/`

## rsync 배포

### 전체 configs 배포

```bash
rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
  configs/ <user>@<MONITORING_VM_IP>:~/basphere-observability/configs/
```

### Grafana 대시보드만 배포

```bash
rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
  configs/grafana/provisioning/dashboards/json/ \
  <user>@<MONITORING_VM_IP>:~/basphere-observability/configs/grafana/provisioning/dashboards/json/
```

### Alert 규칙만 배포

```bash
rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
  configs/vmalert/alerts/ \
  <user>@<MONITORING_VM_IP>:~/basphere-observability/configs/vmalert/alerts/
```

### docker-compose.yml 배포

```bash
rsync -avz -e "ssh -i ~/.ssh/<your-key>" \
  docker-compose.yml <user>@<MONITORING_VM_IP>:~/basphere-observability/
```

## Docker Compose 서비스 재시작

```bash
# 원격에서 실행
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP> \
  "cd ~/basphere-observability && docker compose restart <service>"
```

### 주요 서비스별 명령어

| 변경 대상 | 재시작 명령 |
|-----------|------------|
| 대시보드 JSON | `docker compose restart grafana` |
| Alert 규칙 | `docker compose restart vmalert` |
| Alertmanager 설정 | `docker compose restart alertmanager` |
| scrape 설정 | `docker compose restart victoriametrics` |
| Loki/Promtail 설정 | `docker compose restart loki promtail` |
| 전체 스택 | `docker compose down && docker compose up -d` |

## 환경변수 설정

```bash
# 서버에서 .env 파일 생성
cp .env.example .env
vi .env  # 실제 값 입력
```

주요 환경변수:
- `MONITORING_VM_IP` - 모니터링 VM IP
- `GF_ADMIN_USER` / `GF_ADMIN_PASSWORD` - Grafana 관리자
- `DISCORD_WEBHOOK_URL` - Discord 알림 웹훅
- `VCENTER_HOST` / `VCENTER_USER` / `VCENTER_PASSWORD` - vCenter 연동
- `OPNSENSE_API_KEY` / `OPNSENSE_API_SECRET` - OPNsense API

## 배포 후 검증 체크리스트

- [ ] Grafana 접속 확인: `https://<your-grafana-domain>`
- [ ] VictoriaMetrics 헬스: `curl http://<MONITORING_VM_IP>:8428/-/healthy`
- [ ] vmalert 상태: `http://<MONITORING_VM_IP>:8880/api/v1/rules`
- [ ] Alertmanager 상태: `http://<MONITORING_VM_IP>:9093/#/status`
- [ ] Loki ready: `curl http://<MONITORING_VM_IP>:3100/ready`
- [ ] Docker 컨테이너 상태: `docker ps --format "table {{.Names}}\t{{.Status}}"`
- [ ] 대시보드에서 데이터 표시 확인 (최근 5분)
