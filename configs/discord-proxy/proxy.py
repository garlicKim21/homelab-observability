"""Alertmanager -> Discord webhook proxy.

Receives Alertmanager webhook POST, converts to Discord embed format,
and forwards to the Discord webhook URL from DISCORD_WEBHOOK env var.
"""

import http.server
import json
import os
import urllib.request
import urllib.error

DISCORD_WEBHOOK = os.environ.get("DISCORD_WEBHOOK", "")
DISCORD_USERNAME = os.environ.get("DISCORD_USERNAME", "Alertmanager")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9094"))

COLORS = {
    "critical": 0xFF0000,  # red
    "warning": 0xFFA500,   # orange
    "info": 0x0000FF,      # blue
    "resolved": 0x00FF00,  # green
}


def build_embeds(data):
    """Convert Alertmanager webhook payload to Discord embeds."""
    embeds = []
    status = data.get("status", "unknown")
    alerts = data.get("alerts", [])

    for alert in alerts:
        alert_status = alert.get("status", status)
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        severity = labels.get("severity", "info")

        if alert_status == "resolved":
            color = COLORS["resolved"]
            title_prefix = "[RESOLVED]"
        else:
            color = COLORS.get(severity, COLORS["info"])
            title_prefix = f"[{severity.upper()}]"

        alertname = labels.get("alertname", "Unknown")
        summary = annotations.get("summary", "")
        description = annotations.get("description", "")

        fields = []
        for key, val in labels.items():
            if key not in ("alertname", "severity", "__name__"):
                fields.append({"name": key, "value": str(val), "inline": True})

        embed = {
            "title": f"{title_prefix} {alertname}",
            "description": summary or description or "No description",
            "color": color,
            "fields": fields[:25],  # Discord limit
        }

        if description and summary:
            embed["description"] = f"{summary}\n{description}"

        embeds.append(embed)

    return embeds


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid JSON")
            return

        embeds = build_embeds(data)
        if not embeds:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"No alerts")
            return

        # Discord allows max 10 embeds per message
        for i in range(0, len(embeds), 10):
            chunk = embeds[i : i + 10]
            payload = json.dumps(
                {"username": DISCORD_USERNAME, "embeds": chunk}
            ).encode()

            req = urllib.request.Request(
                DISCORD_WEBHOOK,
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "Basphere-AlertProxy/1.0",
                },
                method="POST",
            )

            try:
                with urllib.request.urlopen(req, timeout=10) as resp:
                    print(f"Discord OK: {resp.status} ({len(chunk)} embeds)")
            except urllib.error.HTTPError as e:
                err_body = e.read().decode(errors="replace")
                print(f"Discord error {e.code}: {err_body}")
            except Exception as e:
                print(f"Discord request failed: {e}")

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}")


if __name__ == "__main__":
    if not DISCORD_WEBHOOK:
        print("ERROR: DISCORD_WEBHOOK not set")
        exit(1)

    print(f"Listening on 0.0.0.0:{LISTEN_PORT}")
    server = http.server.HTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    server.serve_forever()
