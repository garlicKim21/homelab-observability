#!/usr/bin/env bash
# =============================================================================
# deploy.sh - Git Pull + IP 치환 기반 배포 스크립트
# 서버의 .env에서 IP를 읽어 config 플레이스홀더를 자동 치환 후 배포
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ---- .env 로드 ----
if [[ ! -f .env ]]; then
  echo "[ERROR] .env 파일이 없습니다. 서버에 .env를 먼저 설정하세요."
  exit 1
fi
set -a
source .env
set +a

# ---- 필수 변수 확인 ----
REQUIRED_VARS=(OCI_INSTANCE_IP AP_IP FIREWALL_IP_1 FIREWALL_IP_2 FIREWALL_IP_3 ESXI_IP_PATTERN NAS_IP)
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] .env에 ${var}가 설정되지 않았습니다."
    exit 1
  fi
done

# ---- Git Pull ----
echo "=== Git Pull ==="
git pull origin main
echo ""

# ---- IP 치환 (Python) ----
echo "=== IP 치환 ==="
python3 << 'PYEOF'
import os, re, sys

def escape_dots(ip):
    """LogQL regex selector용: . → \\."""
    return ip.replace(".", "\\.")

env = os.environ

# --- scrape.yml: plain IP 치환 ---
scrape_path = "configs/victoriametrics/scrape.yml"
with open(scrape_path, "r") as f:
    content = f.read()

content = content.replace("<OCI_INSTANCE_IP>", env["OCI_INSTANCE_IP"])
content = content.replace("<AP_IP>", env["AP_IP"])

with open(scrape_path, "w") as f:
    f.write(content)

remaining = re.findall(r"<[A-Z_]+>", content)
if remaining:
    print(f"[WARN] scrape.yml에 미치환 플레이스홀더: {remaining}", file=sys.stderr)
else:
    print(f"  [OK] {scrape_path}")

# --- promtail-config.yml ---
promtail_path = "configs/promtail/promtail-config.yml"
with open(promtail_path, "r") as f:
    content = f.read()

# regex selector (=~): dots를 escape 처리
fw1 = escape_dots(env["FIREWALL_IP_1"])
fw2 = escape_dots(env["FIREWALL_IP_2"])
fw3 = escape_dots(env["FIREWALL_IP_3"])
esxi = escape_dots(env["ESXI_IP_PATTERN"])

content = content.replace("<FIREWALL_IP_1>", fw1)
content = content.replace("<FIREWALL_IP_2>", fw2)
content = content.replace("<FIREWALL_IP_3>", fw3)
content = content.replace("<ESXI_IP_PATTERN>", esxi)

# exact selector (=): plain IP
content = content.replace("<NAS_IP>", env["NAS_IP"])

with open(promtail_path, "w") as f:
    f.write(content)

remaining = re.findall(r"<[A-Z_]+>", content)
if remaining:
    print(f"[WARN] promtail-config.yml에 미치환 플레이스홀더: {remaining}", file=sys.stderr)
else:
    print(f"  [OK] {promtail_path}")

print("")
PYEOF

# ---- Docker Compose ----
echo "=== Docker Compose Up ==="
docker compose up -d
echo ""

# ---- 상태 확인 ----
echo "=== 컨테이너 상태 ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
echo ""

# ---- 플레이스홀더 잔존 검사 ----
echo "=== 플레이스홀더 잔존 검사 ==="
FAIL=0
if grep -q '<[A-Z_]*>' configs/victoriametrics/scrape.yml 2>/dev/null; then
  echo "[FAIL] scrape.yml에 플레이스홀더 잔존!"
  grep '<[A-Z_]*>' configs/victoriametrics/scrape.yml
  FAIL=1
fi
if grep -q '<[A-Z_]*>' configs/promtail/promtail-config.yml 2>/dev/null; then
  echo "[FAIL] promtail-config.yml에 플레이스홀더 잔존!"
  grep '<[A-Z_]*>' configs/promtail/promtail-config.yml
  FAIL=1
fi
if [[ $FAIL -eq 0 ]]; then
  echo "  [OK] 플레이스홀더 없음"
fi
echo ""
echo "=== 배포 완료 ==="
