# Deployment Guide

## SSH 접속

```bash
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP>
```

- User: `.env`의 SSH 설정 참조
- Host: `.env`의 `MONITORING_VM_IP` 참조
- Remote path: `~/basphere-observability/` (git clone 기반)

## 배포 워크플로우

**로컬 수정 → git push → 서버 SSH → `./deploy.sh`**

### 1. 로컬에서 변경 후 push

```bash
git add -A && git commit -m "변경 내용" && git push
```

### 2. 서버에서 deploy.sh 실행

```bash
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP> \
  "cd ~/basphere-observability && ./deploy.sh"
```

`deploy.sh`가 자동으로 수행하는 작업:
1. `git pull` (자기 업데이트 감지 시 exec 재실행)
2. Python으로 `.env` 기반 플레이스홀더 치환 (`scrape.yml`, `promtail-config.yml`, `snmp.yml`)
3. `docker compose up -d`
4. `vmalert` config reload (`/-/reload` API)
5. 잔존 검사

### 주의사항

- **rsync/scp 수동 배포 금지** — deploy.sh가 자동 처리
- 서버의 치환된 파일은 deploy.sh가 `git pull` 전에 `git checkout --`으로 복원
- docker-compose.yml 내 `${VAR}` 비밀번호에 `$` 포함 불가 (compose가 변수 확장 시도)

## Docker Compose 서비스

### 서비스 목록 (12개)

| 서비스 | 포트 | 용도 |
|--------|------|------|
| victoriametrics | :8428, :8089 | 시계열 DB (HTTP + InfluxDB protocol) |
| vmalert | :8880 | Alert 규칙 평가 |
| alertmanager | :9093 | 알림 라우팅 |
| grafana | :3000 | 시각화 대시보드 |
| telegraf | (push) | vSphere 전체 메트릭 수집 (vCenter API → InfluxDB protocol) |
| snmp_exporter | :9116 | SNMP 장비 메트릭 (스위치, NAS, AP) |
| opnsense-exporter | :8080 | OPNsense API 메트릭 |
| blackbox_exporter | :9115 | HTTP/HTTPS 엔드포인트 프로빙 |
| cadvisor | :8081 | 컨테이너 리소스 모니터링 |
| loki | :3100 | 로그 집계 |
| promtail | :1514 | Syslog 수신 → Loki 전송 |
| discord-webhook-proxy | :9094 | Alertmanager → Discord 변환 |

### 개별 서비스 재시작

```bash
# 원격에서 실행
ssh -i ~/.ssh/<your-key> <user>@<MONITORING_VM_IP> \
  "cd ~/basphere-observability && docker compose restart <service>"
```

| 변경 대상 | 재시작 명령 |
|-----------|------------|
| 대시보드 JSON | `docker compose restart grafana` |
| Alert 규칙 | `curl -X POST http://localhost:8880/-/reload` (vmalert hot reload) |
| Alertmanager 설정 | `docker compose restart alertmanager` |
| scrape 설정 | `docker compose restart victoriametrics` |
| Telegraf 설정 | `docker compose restart telegraf` |
| Loki/Promtail 설정 | `docker compose restart loki promtail` |
| 전체 스택 | `docker compose down && docker compose up -d` |
| 고아 컨테이너 정리 | `docker compose down --remove-orphans && docker compose up -d` |

## 환경변수 설정

```bash
# 서버에서 .env 파일 생성
cp .env.example .env
vi .env  # 실제 값 입력
```

주요 환경변수:
- `MONITORING_VM_IP` - 모니터링 VM IP
- `DNS_SERVER` - 내부 DNS 서버 IP
- `GF_ADMIN_USER` / `GF_ADMIN_PASSWORD` - Grafana 관리자
- `DISCORD_WEBHOOK_URL` - Discord 알림 웹훅
- `VCENTER_HOST` / `VCENTER_USER` / `VCENTER_PASSWORD` - vCenter 연동 (Telegraf)
- `OPNSENSE_API_KEY` / `OPNSENSE_API_SECRET` - OPNsense API

## 배포 후 검증 체크리스트

- [ ] Grafana 접속 확인: `https://grafana.basphere.dev`
- [ ] VictoriaMetrics 헬스: `curl http://localhost:8428/-/healthy`
- [ ] vmalert 상태: `curl http://localhost:8880/api/v1/rules`
- [ ] Alertmanager 상태: `http://localhost:9093/#/status`
- [ ] Loki ready: `curl http://localhost:3100/ready`
- [ ] Docker 컨테이너 상태: `docker ps --format "table {{.Names}}\t{{.Status}}"`
- [ ] 대시보드에서 데이터 표시 확인 (최근 5분)
- [ ] Telegraf vSphere 메트릭 확인: `curl 'http://localhost:8428/api/v1/query?query=vsphere_host_cpu_usage_average'`
