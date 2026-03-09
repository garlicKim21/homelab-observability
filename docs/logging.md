# Logging Architecture

홈랩 인프라 로그 수집 아키텍처. 모든 로그는 **Loki**에 집중되며, **Promtail**이 수집/파싱, **rsyslog**가 포맷 변환을 담당한다.

## 수집 경로 요약

| 장비 | 프로토콜 | 수신자 | Promtail Job | device_type | host | 비고 |
|------|----------|--------|-------------|-------------|------|------|
| OPNsense | TCP 1514 | Promtail 직접 | `syslog_tcp` | `firewall` | `cerberus.basphere.local` | RFC 5424, notice 이상 전송 |
| Synology NAS | TCP 1514 | Promtail 직접 | `syslog_tcp` | `nas` | `BasphereStorage` | RFC 5424 (IETF), info 이상 전송 |
| ESXi 6대 | UDP 1514 | rsyslog 릴레이 | `syslog_relay` | `esxi` | `esxi01`~`esxi06` | RFC 3164→5424 변환, warning 이상 |
| vCenter (vcsa) | UDP 1514 | rsyslog 릴레이 | `syslog_relay` | `vcenter` | `vcsa` | RFC 3164→5424 변환, warning 이상 |
| TP-Link SG2218 | UDP 514 | rsyslog 릴레이 | `syslog_relay` | `switch` | `SG2218` | 비표준→hostname 고정 후 전달 |
| Observer 컨테이너 (13개) | Docker socket | Promtail 직접 | `docker` | `container` | `observer` | Docker SD, 전체 수집 |
| Observer 호스트 | 파일 읽기 | Promtail 직접 | `host_logs` | `server` | `observer` | syslog, auth.log, kern.log |
| Ratatosk 컨테이너 (OCI) | Docker socket | 원격 Promtail | `docker` | `application` | `ratatosk` | 별도 Promtail 인스턴스 |
| Ratatosk 호스트 (OCI) | 파일 읽기 | 원격 Promtail | `host_logs` | `cloud` | `ratatosk` | syslog, auth.log, kern.log |

## 아키텍처 다이어그램

```
┌─ TCP 1514 (RFC 5424 직접) ─────────────────────────────────────┐
│  OPNsense ──TCP──┐                                              │
│  NAS ────────TCP──┼──→ Promtail (syslog_tcp, :1514)             │
└───────────────────┘                                              │
                                                                   ├──→ Loki (:3100)
┌─ UDP → rsyslog → TCP 1515 (RFC 3164→5424 변환) ───────────────┐│
│  ESXi×6 ──UDP 1514──┐                                          ││
│  vCenter ─UDP 1514──┼──→ rsyslog ──TCP──→ Promtail (syslog_relay, :1515)
│  Switch ──UDP 514───┘    (warning+ 필터,                        ││
│                           hostname 고정)                         ││
└─────────────────────────────────────────────────────────────────┘│
                                                                   │
┌─ Docker + Host Logs ───────────────────────────────────────────┐│
│  Observer 컨테이너 ──Docker SD──→ Promtail (docker)             ├┘
│  Observer 호스트 로그 ──파일──→ Promtail (host_logs)            │
└─────────────────────────────────────────────────────────────────┘

┌─ 원격 (OCI) ───────────────────────────────────────────────────┐
│  Ratatosk 컨테이너 ──Docker SD──┐                               │
│  Ratatosk 호스트 로그 ──파일────┼──→ 원격 Promtail ──HTTP──→ Loki
└─────────────────────────────────┘                               │
```

## 컴포넌트 상세

### Promtail (Observer)

- **이미지**: `grafana/promtail:3.3.2`
- **리소스**: mem 512m, cpu 0.5
- **설정 파일**: `configs/promtail/promtail-config.yml`
- **Positions**: `/data/promtail/positions.yaml` (영속화)

**Scrape Jobs:**

| Job | 포트/소스 | 설명 |
|-----|----------|------|
| `docker` | Docker socket | Observer 컨테이너 13개 자동 발견 |
| `host_logs` | `/var/log/host/*` | Observer 호스트 syslog, auth, kernel |
| `syslog_tcp` | TCP 1514 | OPNsense, NAS 직접 수신 (RFC 5424) |
| `syslog_relay` | TCP 1515 | rsyslog 릴레이 경유 (ESXi, vCenter, Switch) |

**device_type 분류 로직:**
- `syslog_tcp`: 소스 IP 기반 (`host_ip` 라벨로 firewall/esxi/nas 분류)
- `syslog_relay`: hostname 기반 (`esxi*`→esxi, `vcsa`→vcenter, `SG2218`→switch)
- `docker`: 정적 (`container`)
- `host_logs`: 정적 (`server`)

### Promtail (Ratatosk/OCI)

- **설정 파일**: `configs/promtail/promtail-remote-oci.yml`
- **리소스**: mem 256m, cpu 0.25
- **전송 대상**: `http://<OBSERVER_IP>:3100/loki/api/v1/push`
- **device_type**: 컨테이너=`application`, 호스트=`cloud`

### rsyslog

- **설정 파일**: `configs/rsyslog/rsyslog.conf`
- **리소스**: mem 64m, cpu 0.1
- **역할**: RFC 3164 → RFC 5424 변환 릴레이

| 수신 포트 | 프로토콜 | Ruleset | 필터 | 출력 |
|-----------|----------|---------|------|------|
| UDP 1514 | UDP | `esxi_vcenter` | severity ≤ 4 (warning 이상) | TCP→Promtail:1515 |
| UDP 514 | UDP | `switch` | 전체 | TCP→Promtail:1515 (hostname=SG2218 고정) |

### Loki

- **이미지**: `grafana/loki:3.3.2`
- **리소스**: mem 1024m, cpu 1.0
- **설정 파일**: `configs/loki/loki-config.yml`
- **스토리지**: `/data/loki` (filesystem, TSDB)
- **보존 기간**: 30일 (`retention_period: 720h`)
- **Ruler**: 활성화 (`auth_enabled: false` → tenant "fake")
- **Alertmanager 연동**: `http://alertmanager:9093`

## Severity 정규화

RFC 5424 원본 값과 애플리케이션 축약값이 혼재하므로, Promtail pipeline에서 수집 시점에 통일한다.

| RFC 5424 원본 | 정규화 결과 | 적용 위치 |
|---------------|------------|----------|
| `informational` | `info` | syslog_tcp, syslog_relay |
| `warn` | `warning` | docker, host_logs, 원격 Promtail |
| `err` | `error` | docker, host_logs, 원격 Promtail |
| `crit` | `critical` | docker, host_logs, 원격 Promtail |

**정규화 파이프라인 (syslog jobs):**
```yaml
- template:
    source: severity
    template: '{{ if eq .Value "informational" }}info{{ else }}{{ .Value }}{{ end }}'
- labels:
    severity:
```

**정규화 파이프라인 (docker/host jobs):**
```yaml
- template:
    source: severity
    template: "{{ $l := ToLower .level }}{{ if eq $l \"warn\" }}warning{{ else if eq $l \"err\" }}error{{ else if eq $l \"crit\" }}critical{{ else }}{{ $l }}{{ end }}"
- labels:
    severity:
```

## 로그 파싱 파이프라인

### Docker 컨테이너 (Observer)

| 서비스 | 파서 | 대상 |
|--------|------|------|
| `grafana`, `loki` | JSON (`level` 필드) | severity 추출 |
| `victoriametrics`, `vmalert`, `alertmanager`, `snmp_exporter`, `blackbox_exporter`, `opnsense-exporter`, `promtail` | logfmt (`level` 필드) | severity 추출 |
| `telegraf` | regex (prefix 기반) | severity 추출 |
| 기타 (`cadvisor`, `rsyslog`, `discord-webhook-proxy`) | regex fallback | 로그 본문에서 severity 키워드 검색 |

### Docker 컨테이너 (Ratatosk/OCI)

| 서비스 | 파서 | 대상 |
|--------|------|------|
| `*postgres*` | regex (PostgreSQL 로그 포맷) | `LOG`→`info` 변환 포함 |
| 기타 | regex fallback | 본문에서 severity 키워드 검색 |

## 로그 기반 알림 규칙

Loki Ruler로 LogQL 알림을 평가하여 Alertmanager로 전송한다.

**설정 파일**: `configs/loki/rules/container-log-alerts.yml`

### container-log-alerts

| 알림 | 심각도 | 조건 | 비고 |
|------|--------|------|------|
| `ContainerErrorLogSpike` | warning | 컨테이너별 에러 이상 로그 5분간 >10건 | |
| `ContainerOOMDetected` | critical | OOM 키워드 5분간 >0건 | `container_name!="loki"` (자기참조 방지) |
| `ContainerConnectionRefused` | warning | connection refused 5분간 >5건 | `container_name!="loki"` (자기참조 방지) |

### host-log-alerts

| 알림 | 심각도 | 조건 | 비고 |
|------|--------|------|------|
| `SSHBruteForceAttempt` | warning | SSH 인증 실패 5분간 >10건 | `device_type="server"`, `log_type="auth"` |
| `KernelCriticalError` | critical | 커널 패닉/하드웨어 에러 5분간 >0건 | `device_type="server"`, `log_type="kernel"` |

> **Loki Ruler 주의사항**: Loki 알림은 VictoriaMetrics `ALERTS` 메트릭에 포함되지 않는다. Grafana에서 Loki 알림을 표시하려면 Alertmanager 데이터소스를 사용해야 한다.

> **자기참조 방지**: Loki Ruler가 LogQL을 평가하면 쿼리 텍스트가 Loki 자체 로그에 기록된다. "OOM", "connection refused" 등의 키워드가 쿼리에 포함되어 있으므로, Loki 컨테이너 로그를 검색 대상에서 제외해야 무한 루프(false positive)를 방지할 수 있다.

## 장비별 로그 레벨 설정

| 장비 | 전송 레벨 | 설정 위치 | 필터 주체 |
|------|----------|----------|----------|
| OPNsense | notice 이상 | OPNsense Web UI → System → Settings → Logging | 장비 자체 |
| Synology NAS | info 이상 (전체) | DSM → Log Center → 로그 전송 | 장비 자체 |
| ESXi 6대 | warning 이상 | rsyslog `$syslogseverity > 4 then stop` | rsyslog 필터 |
| vCenter | warning 이상 | rsyslog `$syslogseverity > 4 then stop` | rsyslog 필터 |
| TP-Link Switch | 전체 | rsyslog ruleset (필터 없음) | 전체 전달 |
| Observer 컨테이너 | 전체 | Docker SD (필터 없음) | 전체 수집 |
| Observer 호스트 | 전체 | 파일 읽기 (필터 없음) | 전체 수집 |
| Ratatosk 컨테이너 | 전체 | Docker SD (필터 없음) | 전체 수집 |
| Ratatosk 호스트 | 전체 | 파일 읽기 (필터 없음) | 전체 수집 |

## Loki 라벨 체계

| 라벨 | 설명 | 값 예시 |
|------|------|--------|
| `device_type` | 장비 유형 | `firewall`, `nas`, `esxi`, `vcenter`, `switch`, `container`, `server`, `application`, `cloud` |
| `host` | 장비 호스트명 | `cerberus.basphere.local`, `BasphereStorage`, `esxi01`~`esxi06`, `vcsa`, `SG2218`, `observer`, `ratatosk` |
| `host_ip` | 소스 IP (syslog_tcp만) | IP 주소 |
| `severity` | 로그 심각도 (정규화됨) | `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency` |
| `facility` | syslog facility | `kern`, `user`, `daemon`, `local0`~`local7` 등 |
| `app` | syslog app name | `syslog-ng`, `filterlog`, `configd.py` 등 |
| `container_name` | 컨테이너 이름 (docker job) | `grafana`, `loki`, `promtail` 등 |
| `service` | compose 서비스 이름 (docker job) | `grafana`, `loki` 등 |
| `log_type` | 호스트 로그 유형 (host_logs) | `syslog`, `auth`, `kernel` |
| `job` | Promtail job 이름 | `syslog`, `docker`, `host_logs` |
| `transport` | 전송 프로토콜 (syslog_tcp만) | `tcp` |

## 플레이스홀더 (Public Repo)

실제 IP는 서버 `.env`에만 보관하며, git에는 플레이스홀더로 관리한다. `deploy.sh`가 배포 시 자동 치환.

| 플레이스홀더 | 용도 | 파일 |
|-------------|------|------|
| `<FIREWALL_IP_1\|2\|3>` | OPNsense 방화벽 IP 3개 | promtail-config.yml |
| `<ESXI_IP_PATTERN>` | ESXi 호스트 IP 패턴 | promtail-config.yml |
| `<NAS_IP>` | Synology NAS IP | promtail-config.yml |
| `<OBSERVER_IP>` | Observer 서버 IP | promtail-remote-oci.yml |

## 트러블슈팅

### syslog 수신 확인
```bash
# Promtail syslog 에러 확인
docker logs promtail --since 5m 2>&1 | grep "error initializing syslog"

# TCP 1514 연결 상태
ss -tn "sport = :1514"

# 특정 장비 트래픽 캡처
sudo tcpdump -i ens33 "host <IP> and tcp port 1514" -A -n -c 10

# Loki에서 최근 로그 확인
curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={device_type="firewall"}' \
  --data-urlencode "limit=5" \
  --data-urlencode "start=$(date -u -d '5 min ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000"
```

### 장비 재시작 후 로그 안 들어올 때
1. 장비 syslog 설정 확인 (IP, 포트, 프로토콜, TLS 비활성화)
2. 장비에서 syslog 서비스 껐다 켜기 (설정 재적용)
3. Promtail 로그에서 `error initializing syslog stream` 확인
4. `tcpdump`로 데이터가 실제로 도달하는지 확인

### severity 라벨 이상
- Loki에서 `informational` 등 정규화되지 않은 값이 보이면 Promtail 재시작 필요
- `curl -s "http://localhost:3100/loki/api/v1/label/severity/values"` 로 현재 라벨 값 확인
