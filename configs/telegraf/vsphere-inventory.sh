#!/usr/bin/env bash
# =============================================================================
# vCenter Inventory Collector for Telegraf inputs.exec
# govc CLI → InfluxDB line protocol
#
# Metrics:
#   vsphere_inventory_vm_total, vm_powered_on, vm_powered_off, vm_templates
#   vsphere_inventory_vm_snapshot_total, vm_snapshots (per VM)
#   vsphere_inventory_cluster_hosts, cluster_hosts_effective
#   vsphere_inventory_cluster_vmotion_total
# =============================================================================
set -euo pipefail

export GOVC_URL="https://${VCENTER_HOST}"
export GOVC_USERNAME="${VCENTER_USER}"
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_INSECURE=true

# --- VM 메트릭 ---
vm_paths=$(govc find / -type m 2>/dev/null || true)
vm_total=0
powered_on=0
powered_off=0
vm_templates=0
snapshot_total=0
snapshot_lines=""

if [[ -n "$vm_paths" ]]; then
  # govc vm.info -json accepts multiple paths
  vm_info=$(govc vm.info -json $vm_paths 2>/dev/null || echo '{}')

  # Count VMs excluding templates (config.template == true)
  vm_total=$(echo "$vm_info" | jq '[.virtualMachines[] | select(.config.template != true)] | length' 2>/dev/null || echo 0)
  vm_templates=$(echo "$vm_info" | jq '[.virtualMachines[] | select(.config.template == true)] | length' 2>/dev/null || echo 0)

  # Count power states excluding templates
  powered_on=$(echo "$vm_info" | jq '[.virtualMachines[] | select(.config.template != true) | select(.runtime.powerState == "poweredOn")] | length' 2>/dev/null || echo 0)
  powered_off=$(echo "$vm_info" | jq '[.virtualMachines[] | select(.config.template != true) | select(.runtime.powerState == "poweredOff")] | length' 2>/dev/null || echo 0)

  # Count snapshots per VM (excluding templates)
  while IFS=$'\t' read -r vm_name snap_count; do
    [[ -z "$vm_name" || "$snap_count" == "0" ]] && continue
    escaped_name=$(echo "$vm_name" | sed 's/ /\\ /g; s/,/\\,/g; s/=/\\=/g')
    snapshot_lines="${snapshot_lines}vsphere_inventory_vm_snapshots,vmname=${escaped_name} value=${snap_count}i
"
    snapshot_total=$((snapshot_total + snap_count))
  done < <(echo "$vm_info" | jq -r '
    .virtualMachines[] | select(.config.template != true) |
    [.name, (if .snapshot then [.snapshot.rootSnapshotList | .. | objects | select(has("name"))] | length else 0 end)] |
    @tsv
  ' 2>/dev/null || true)
fi

echo "vsphere_inventory_vm_total value=${vm_total}i"
echo "vsphere_inventory_vm_powered_on value=${powered_on}i"
echo "vsphere_inventory_vm_powered_off value=${powered_off}i"
echo "vsphere_inventory_vm_templates value=${vm_templates}i"
[[ -n "$snapshot_lines" ]] && printf '%s' "$snapshot_lines"
echo "vsphere_inventory_vm_snapshot_total value=${snapshot_total}i"

# --- 클러스터 메트릭 ---
cluster_paths=$(govc find / -type c 2>/dev/null || true)
while IFS= read -r cluster_path; do
  [[ -z "$cluster_path" ]] && continue
  cluster_name=$(basename "$cluster_path")
  escaped_cluster=$(echo "$cluster_name" | sed 's/ /\\ /g; s/,/\\,/g; s/=/\\=/g')

  cluster_json=$(govc object.collect -json "$cluster_path" summary 2>/dev/null || echo '{}')

  num_hosts=$(echo "$cluster_json" | jq -r '.[0].val.numHosts // 0' 2>/dev/null || echo 0)
  num_effective=$(echo "$cluster_json" | jq -r '.[0].val.numEffectiveHosts // 0' 2>/dev/null || echo 0)
  num_vmotions=$(echo "$cluster_json" | jq -r '.[0].val.numVmotions // 0' 2>/dev/null || echo 0)

  echo "vsphere_inventory_cluster_hosts,clustername=${escaped_cluster} value=${num_hosts}i"
  echo "vsphere_inventory_cluster_hosts_effective,clustername=${escaped_cluster} value=${num_effective}i"
  echo "vsphere_inventory_cluster_vmotion_total,clustername=${escaped_cluster} value=${num_vmotions}i"
done <<< "$cluster_paths"
