#!/usr/bin/env bash
# =============================================================================
# vCenter Inventory Collector for Telegraf inputs.exec
# govc CLI로 vCenter API 호출 → InfluxDB line protocol 출력
#
# Metrics:
#   vsphere_inventory_vm_total, vm_powered_on, vm_powered_off
#   vsphere_inventory_vm_snapshot_total, vm_snapshots (per VM)
#   vsphere_inventory_cluster_hosts, cluster_hosts_effective
#   vsphere_inventory_cluster_vmotion_total
# =============================================================================
set -euo pipefail

# govc 환경변수 (Telegraf 환경변수에서 매핑)
export GOVC_URL="https://${VCENTER_HOST}"
export GOVC_USERNAME="${VCENTER_USER}"
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_INSECURE=true

# --- VM 메트릭 ---
vm_json=$(govc find / -type m -json 2>/dev/null || echo "[]")
vm_total=$(echo "$vm_json" | jq 'length')

powered_on=0
powered_off=0
snapshot_total=0

if [[ "$vm_total" -gt 0 ]]; then
  vm_details=$(govc ls -json -l $(echo "$vm_json" | jq -r '.[]') 2>/dev/null || echo '{}')

  # govc vm.info로 power state 수집
  while IFS= read -r line; do
    name=$(echo "$line" | jq -r '.Name')
    power=$(echo "$line" | jq -r '.Runtime.PowerState')
    snap_path=$(echo "$line" | jq -r '.Snapshot.RootSnapshotList // empty')

    case "$power" in
      poweredOn)  ((powered_on++)) ;;
      poweredOff) ((powered_off++)) ;;
    esac
  done < <(govc vm.info -json $(echo "$vm_json" | jq -r '.[]') 2>/dev/null | jq -c '.virtualMachines[]')

  # 스냅샷 수집
  while IFS=$'\t' read -r vm_name snap_count; do
    if [[ "$snap_count" -gt 0 ]]; then
      escaped_name=$(echo "$vm_name" | sed 's/ /\\ /g; s/,/\\,/g; s/=/\\=/g')
      echo "vsphere_inventory_vm_snapshots,vmname=${escaped_name} value=${snap_count}i"
      snapshot_total=$((snapshot_total + snap_count))
    fi
  done < <(govc snapshot.tree -json $(echo "$vm_json" | jq -r '.[]') 2>/dev/null | \
    jq -r 'to_entries[] | [.key, (.value | [.. | objects | select(has("name"))] | length)] | @tsv' 2>/dev/null || true)
fi

echo "vsphere_inventory_vm_total value=${vm_total}i"
echo "vsphere_inventory_vm_powered_on value=${powered_on}i"
echo "vsphere_inventory_vm_powered_off value=${powered_off}i"
echo "vsphere_inventory_vm_snapshot_total value=${snapshot_total}i"

# --- 클러스터 메트릭 ---
while IFS= read -r cluster_path; do
  [[ -z "$cluster_path" ]] && continue
  cluster_name=$(basename "$cluster_path")
  escaped_cluster=$(echo "$cluster_name" | sed 's/ /\\ /g; s/,/\\,/g; s/=/\\=/g')

  cluster_json=$(govc object.collect -json "$cluster_path" summary 2>/dev/null || echo '{}')

  num_hosts=$(echo "$cluster_json" | jq -r '.[0].Val.NumHosts // 0')
  num_effective=$(echo "$cluster_json" | jq -r '.[0].Val.NumEffectiveHosts // 0')
  num_vmotions=$(echo "$cluster_json" | jq -r '.[0].Val.NumVmotions // 0')

  echo "vsphere_inventory_cluster_hosts,clustername=${escaped_cluster} value=${num_hosts}i"
  echo "vsphere_inventory_cluster_hosts_effective,clustername=${escaped_cluster} value=${num_effective}i"
  echo "vsphere_inventory_cluster_vmotion_total,clustername=${escaped_cluster} value=${num_vmotions}i"
done < <(govc find / -type c 2>/dev/null || true)
