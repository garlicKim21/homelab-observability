# Grafana Dashboard Style Guide

대시보드 UI 일관성을 위한 디자인 규칙. 새 대시보드를 만들거나 기존 대시보드를 수정할 때 반드시 따를 것.

## System Status Row (맨 상단)

### Status 패널
- **제목**: `Status` (장비 유형 접두어 불필요 — 대시보드 제목이 장비를 식별)
- **legendFormat**: 모델명 사용 (예: `DS1515+`, `SG2218`, `AX3000BMC`, `OPNsense`)
- **textMode**: `value_and_name` — "모델명 UP" 형태로 표시
- **colorMode**: `background` — 배경색으로 상태 표현 (초록=UP, 빨강=DOWN)
- **graphMode**: `none`
- **justifyMode**: `center`

### Uptime 패널
- **제목**: `Uptime`
- **textMode**: `value` — 값만 표시 (패널 제목이 설명)
- **colorMode**: `value` — 텍스트 색상으로 표현 (초록)
- **unit**: `s` (Grafana가 자동으로 "2d 3h" 등으로 변환)
- SNMP 장비: `sysUpTime{job="..."} / 100`
- node_exporter 기반: `node_time_seconds - node_boot_time_seconds`

### 기타 Stat 패널 (Active Interfaces, Temperature 등)
- **textMode**: `value` — 패널 제목이 이미 설명하므로 값만 표시
- **예외**: 여러 시리즈를 하나의 패널에 표시할 때는 `value_and_name` 사용 (예: RAID Status의 Volume 1/Volume 2)

## Overview 대시보드 (Asgard)

### Device Status Row
- **패널 제목**: 모델명 또는 서비스명 사용 (예: `DS1515+`, `SG2218`, `AX3000BMC`, `Ratatosk.io`)
- **textMode**: `value` — UP/DOWN만 표시, 패널 제목이 장비를 식별
- **예외**: RAID Status 등 다중 시리즈 → `value_and_name`

### Resource Utilization
- **패널 제목**: 상단 Device Status의 패널 이름과 동일하게 (예: `DS1515+ CPU`, `SG2218 MEM`)

## 공통 규칙

### 이름 중복 방지
패널 제목과 표시 내용이 겹치면 안 됨:
- BAD: 패널 "Active Interfaces" + 표시 "Active Interfaces 6"
- GOOD: 패널 "Active Interfaces" + 표시 "6"

### 장비 식별자 매핑

| 역할 | 코드명 | 모델명 (패널 제목) |
|------|--------|-------------------|
| Firewall | Cerberus | OPNsense |
| Switch | Bifrost | SG2218 |
| AP | Heimdall | AX3000BMC |
| NAS | Fenrir | DS1515+ |
| OCI | Ratatosk | Ratatosk.io |

### 색상 규칙
- UP / Normal / Healthy: `#73BF69` (초록)
- Warning / Degraded: `#FADE2A` (노랑)
- DOWN / Failed / Crashed: `#F2495C` (빨강)

### Value Mapping (UP/DOWN 패턴)
```json
{
  "type": "value",
  "options": {
    "0": { "text": "DOWN", "color": "#F2495C", "index": 0 },
    "1": { "text": "UP", "color": "#73BF69", "index": 1 }
  }
}
```

### Unix Timestamp 메트릭
`*_last_handshake_seconds` 같은 Unix timestamp 메트릭은 그대로 표시하면 안 됨.
반드시 `time() - metric` 으로 경과 시간을 계산할 것.
