# QRForge - Run 2 Gentler Load Test for Clean HPA Autoscaling
# Target: /api/heavy?size=1024&n=3
# Designed to exceed 50m CPU target without breaching the 200Mi memory ceiling.

from locust import HttpUser, task, between

class GentleLoadUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task
    def generate_gentle_qr(self):
        with self.client.get(
            "/api/heavy?size=1024&n=3",
            name="/api/heavy?size=1024&n=3",
            catch_response=True,
            timeout=30
        ) as resp:
            if resp.status_code == 200:
                resp.success()
            else:
                resp.failure(f"HTTP {resp.status_code}")
