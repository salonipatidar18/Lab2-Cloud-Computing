"""
QRForge — Locust Load Test
===========================
Alternative load generator to 'hey'. Provides a web UI for real-time monitoring.

Install: pip install locust
Run:     locust -f loadtest/locustfile.py --host=http://<EXTERNAL_IP> --users=50 --spawn-rate=5 --run-time=5m --headless
Or UI:   locust -f loadtest/locustfile.py --host=http://<EXTERNAL_IP>
         Then open http://localhost:8089
"""

import json
import random
import time
# pyrefly: ignore [missing-import]
from locust import HttpUser, task, between, events


# ─────────────────────────────────────────────────────────────
# Sample data for realistic QR content
# ─────────────────────────────────────────────────────────────
TEMPLATES = [
    "neon-cyber", "sunset-gradient", "ocean-blue", "forest-green",
    "minimal-mono", "retro-pixel", "royal-gold", "candy-pop"
]

URLS = [
    "https://example.com",
    "https://github.com/qrforge",
    "https://azure.microsoft.com",
    "https://kubernetes.io/docs/home/",
    "https://prometheus.io/docs/",
]

WIFI_DATA = [
    {"ssid": "HomeNetwork", "password": "secret123", "encryption": "WPA"},
    {"ssid": "OfficeWifi",  "password": "workpass!",  "encryption": "WPA"},
    {"ssid": "GuestNet",    "password": "",            "encryption": "nopass"},
]


class QRForgeUser(HttpUser):
    """
    Simulates a real QRForge user:
      - 60% of the time: POST /api/qr  (normal QR generation, uses Redis cache)
      - 25% of the time: GET /api/heavy (CPU-intensive load test endpoint)
      - 10% of the time: GET /api/history or /api/stats
      -  5% of the time: GET /api/templates
    """
    # Each user waits 0.5-2s between tasks (simulates typing/browsing)
    wait_time = between(0.5, 2.0)

    def on_start(self):
        """Called when a user starts — fetch templates to warm up."""
        self.client.get("/api/templates", name="/api/templates")
        self.template = random.choice(TEMPLATES)

    @task(6)
    def generate_qr_url(self):
        """Generate a URL QR code — hits Redis cache frequently."""
        payload = {
            "type":     "url",
            "data":     random.choice(URLS),
            "template": random.choice(TEMPLATES),
            "size":     random.choice([256, 512, 1024]),
            "ecc":      random.choice(["L", "M", "Q"]),
            "format":   random.choice(["png", "svg"]),
        }
        with self.client.post(
            "/api/qr",
            json=payload,
            name="/api/qr [url]",
            catch_response=True
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Status {resp.status_code}: {resp.text[:100]}")

    @task(3)
    def generate_qr_wifi(self):
        """Generate a Wi-Fi QR code."""
        wifi = random.choice(WIFI_DATA)
        payload = {
            "type":       "wifi",
            "ssid":       wifi["ssid"],
            "password":   wifi["password"],
            "encryption": wifi["encryption"],
            "template":   random.choice(TEMPLATES),
            "size":       512,
            "ecc":        "M",
            "format":     "png",
        }
        with self.client.post(
            "/api/qr",
            json=payload,
            name="/api/qr [wifi]",
            catch_response=True
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Status {resp.status_code}: {resp.text[:100]}")

    @task(3)
    def heavy_load(self):
        """
        CPU-intensive endpoint — generates large QR codes without caching.
        This is the primary HPA trigger.
        """
        size = random.choice([1024, 1500, 2000])
        n    = random.choice([5, 8, 10])
        with self.client.get(
            f"/api/heavy?size={size}&n={n}",
            name="/api/heavy",
            catch_response=True,
            timeout=60
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Status {resp.status_code}")

    @task(1)
    def get_history(self):
        self.client.get("/api/history", name="/api/history")

    @task(1)
    def get_stats(self):
        self.client.get("/api/stats", name="/api/stats")

    @task(1)
    def health_check(self):
        with self.client.get("/healthz", name="/healthz", catch_response=True) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"Unhealthy: {resp.status_code}")


# ─────────────────────────────────────────────────────────────
# Event hooks for reporting
# ─────────────────────────────────────────────────────────────
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print("=" * 60)
    print("QRForge Locust Load Test Starting")
    print("Target:", environment.host)
    print("Endpoints: /api/qr (60%), /api/heavy (25%), others (15%)")
    print("=" * 60)

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print("=" * 60)
    print("QRForge Load Test Finished")
    print("Check kubectl get hpa -n qrforge for scaling results")
    print("=" * 60)
