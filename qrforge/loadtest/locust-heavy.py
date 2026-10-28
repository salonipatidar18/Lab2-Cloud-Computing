# QRForge - Dedicated Heavy CPU Load Test for HPA Autoscaling
# Replicates hey -c 50 /api/heavy?size=2000&n=10 with extended timeout

from locust import HttpUser, task

class HeavyLoadUser(HttpUser):
    # Continuous firing without delay to maintain 50 parallel requests
    @task
    def generate_heavy_qr(self):
        with self.client.get(
            "/api/heavy?size=2000&n=10",
            name="/api/heavy?size=2000&n=10",
            catch_response=True,
            timeout=90
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"HTTP {resp.status_code}")
