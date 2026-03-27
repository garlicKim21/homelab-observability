#!/usr/bin/env python3
"""OCI Cloud Metrics Collector for Telegraf exec plugin.

Queries OCI Monitoring API for DRG and VPN namespace metrics,
outputs Influx line protocol to stdout.

Environment variables:
  OCI_PROFILES           - Comma-separated profile names (default: SINGAPORE)
  OCI_{PROFILE}_COMPARTMENT - Compartment OCID for each profile
  OCI_CONFIG_PATH        - OCI config file path (default: /oci/config)
"""
import os
import sys
from datetime import datetime, timedelta, timezone

try:
    import oci
except ImportError:
    print("[ERROR] oci SDK not installed", file=sys.stderr)
    sys.exit(1)

OCI_CONFIG_PATH = os.environ.get("OCI_CONFIG_PATH", "/oci/config")

# ---------------------------------------------------------------------------
# Profile mapping: profile name → OCI config profile name
# Add new tenancies here as they become available
# ---------------------------------------------------------------------------
PROFILE_MAP = {
    "SINGAPORE": {"config_profile": "DEFAULT"},
    # "CHUNCHEON": {"config_profile": "CHUNCHEON"},
    # "OSAKA":     {"config_profile": "OSAKA"},
}

# ---------------------------------------------------------------------------
# Metric definitions
# OCI metric name → Influx field name
# ---------------------------------------------------------------------------
DRG_NAMESPACE = "oci_dynamic_routing_gateway"
DRG_METRICS = {
    "BytesToDrgAttachment": "bytes_to",
    "BytesFromDrgAttachment": "bytes_from",
    "PacketsToDrgAttachment": "packets_to",
    "PacketsFromDrgAttachment": "packets_from",
    "PacketDropsToDrgAttachment": "drops_to",
    "PacketsDropsFromDrgAttachment": "drops_from",
}

VPN_NAMESPACE = "oci_vpn"
VPN_METRICS = {
    "TunnelState": "tunnel_state",
    "BytesSent": "bytes_sent",
    "BytesReceived": "bytes_received",
    "PacketsSent": "packets_sent",
    "PacketsReceived": "packets_received",
    "PacketsError": "packets_error",
}


def load_oci_config(config_profile):
    """Load OCI config, remapping key_file to container mount path.

    oci.config.from_file() validates key_file existence immediately,
    which fails because the host path doesn't exist inside the container.
    We parse the INI file manually and fix the path before validation.
    """
    config = {}
    target_section = config_profile.upper()
    current_section = None

    with open(OCI_CONFIG_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1].upper()
                continue
            if "=" in line and current_section == target_section:
                key, _, value = line.partition("=")
                config[key.strip()] = value.strip()

    # Remap key_file: host path → container mount path
    if "key_file" in config:
        config["key_file"] = "/oci/" + os.path.basename(config["key_file"])

    oci.config.validate_config(config)
    return config


def query_metric(client, compartment_id, namespace, metric_name):
    """Query a single metric from OCI Monitoring API (last 5 minutes)."""
    now = datetime.now(timezone.utc)
    start = now - timedelta(minutes=5)

    details = oci.monitoring.models.SummarizeMetricsDataDetails(
        namespace=namespace,
        query=f"{metric_name}[1m].mean()",
        start_time=start.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        end_time=now.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        resolution="1m",
    )
    response = client.summarize_metrics_data(compartment_id, details)
    return response.data


def escape_tag(value):
    """Escape Influx line protocol tag value."""
    if value is None:
        return "unknown"
    return str(value).replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\=")


def latest_datapoint(metric_item):
    """Return the most recent aggregated datapoint, or None."""
    dps = metric_item.aggregated_datapoints
    if not dps:
        return None
    return max(dps, key=lambda d: d.timestamp)


def ts_nano(dt):
    """Convert datetime to nanosecond Unix timestamp."""
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1_000_000_000)


# ---------------------------------------------------------------------------
# Collectors
# ---------------------------------------------------------------------------
def collect_drg(client, compartment_id, profile):
    """Collect DRG attachment metrics → Influx lines."""
    lines = []
    for oci_name, field in DRG_METRICS.items():
        try:
            data = query_metric(client, compartment_id, DRG_NAMESPACE, oci_name)
        except oci.exceptions.ServiceError as e:
            print(f"[WARN] DRG {oci_name}: {e.message}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"[WARN] DRG {oci_name}: {e}", file=sys.stderr)
            continue

        for item in data:
            dp = latest_datapoint(item)
            if dp is None or dp.value is None:
                continue

            dims = item.dimensions or {}
            tags = [f"profile={escape_tag(profile)}"]
            if dims.get("attachmentType"):
                tags.append(f"attachment_type={escape_tag(dims['attachmentType'])}")
            if dims.get("peerRegion"):
                tags.append(f"peer_region={escape_tag(dims['peerRegion'])}")
            if dims.get("resourceId"):
                tags.append(f"resource_id={escape_tag(dims['resourceId'])}")
            if dims.get("dropType"):
                tags.append(f"drop_type={escape_tag(dims['dropType'])}")

            lines.append(
                f"oci_drg,{','.join(tags)} {field}={dp.value} {ts_nano(dp.timestamp)}"
            )
    return lines


def collect_vpn(client, compartment_id, profile):
    """Collect VPN tunnel metrics → Influx lines."""
    lines = []
    for oci_name, field in VPN_METRICS.items():
        try:
            data = query_metric(client, compartment_id, VPN_NAMESPACE, oci_name)
        except oci.exceptions.ServiceError as e:
            # No VPN in this tenancy → skip silently
            if e.status == 404:
                continue
            print(f"[WARN] VPN {oci_name}: {e.message}", file=sys.stderr)
            continue
        except Exception as e:
            print(f"[WARN] VPN {oci_name}: {e}", file=sys.stderr)
            continue

        for item in data:
            dp = latest_datapoint(item)
            if dp is None or dp.value is None:
                continue

            dims = item.dimensions or {}
            tags = [f"profile={escape_tag(profile)}"]
            if dims.get("publicIp"):
                tags.append(f"public_ip={escape_tag(dims['publicIp'])}")
            if dims.get("parentResourceId"):
                tags.append(f"parent_resource_id={escape_tag(dims['parentResourceId'])}")

            # TunnelState is integer (0=down, 1=up)
            if field == "tunnel_state":
                lines.append(
                    f"oci_vpn,{','.join(tags)} {field}={int(dp.value)}i {ts_nano(dp.timestamp)}"
                )
            else:
                lines.append(
                    f"oci_vpn,{','.join(tags)} {field}={dp.value} {ts_nano(dp.timestamp)}"
                )
    return lines


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    profiles_str = os.environ.get("OCI_PROFILES", "SINGAPORE")
    profiles = [p.strip() for p in profiles_str.split(",") if p.strip()]

    output = []

    for profile in profiles:
        if profile not in PROFILE_MAP:
            print(f"[WARN] Unknown profile: {profile}, skipping", file=sys.stderr)
            continue

        compartment_id = os.environ.get(f"OCI_{profile}_COMPARTMENT")
        if not compartment_id:
            print(
                f"[ERROR] OCI_{profile}_COMPARTMENT env var not set, skipping {profile}",
                file=sys.stderr,
            )
            continue

        try:
            config = load_oci_config(PROFILE_MAP[profile]["config_profile"])
            client = oci.monitoring.MonitoringClient(config)
        except Exception as e:
            print(f"[ERROR] OCI client init failed for {profile}: {e}", file=sys.stderr)
            continue

        output.extend(collect_drg(client, compartment_id, profile.lower()))
        output.extend(collect_vpn(client, compartment_id, profile.lower()))

    # Print all lines to stdout for Telegraf
    for line in output:
        print(line)

    if not output:
        print("[INFO] No metrics collected", file=sys.stderr)


if __name__ == "__main__":
    main()
