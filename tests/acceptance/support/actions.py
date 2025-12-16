from dataclasses import dataclass
from typing import Any, Dict, Optional

from .http import ApiClient, ApiResult


@dataclass
class OrderActions:
    api_client: ApiClient

    def create(
        self,
        *,
        token: str,
        pickup_lat: float = 31.9454,
        pickup_lng: float = 35.9284,
        dropoff_lat: float = 31.9632,
        dropoff_lng: float = 35.9106,
        expected_status: int = 201,
    ) -> int:
        payload = {
            "pickup_lat": pickup_lat,
            "pickup_lng": pickup_lng,
            "dropoff_lat": dropoff_lat,
            "dropoff_lng": dropoff_lng,
        }
        result = self.api_client.post("/orders", token=token, json_body=payload, expected_status=expected_status)
        body = result.json()
        if not body or "order_id" not in body:
            raise AssertionError(f"Order creation failed: {result.text}")
        return body["order_id"]

    def get(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.get(f"/orders/{order_id}", token=token, expected_status=expected_status)

    def cancel(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.post(f"/orders/{order_id}/cancel", token=token, expected_status=expected_status)

    def reserve(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.post(f"/orders/{order_id}/reserve", token=token, expected_status=expected_status)

    def pickup(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.post(f"/orders/{order_id}/pickup", token=token, expected_status=expected_status)

    def deliver(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.post(f"/orders/{order_id}/deliver", token=token, expected_status=expected_status)

    def fail(self, order_id: int, *, token: str, expected_status: int = 200) -> ApiResult:
        return self.api_client.post(f"/orders/{order_id}/fail", token=token, expected_status=expected_status)


@dataclass
class DroneActions:
    api_client: ApiClient
    admin_token: str

    def mark_broken(
        self,
        drone_id: int,
        *,
        lat: float,
        lng: float,
        token: Optional[str] = None,
        via_admin: bool = False,
        expected_status: int = 200,
    ) -> ApiResult:
        payload = {"lat": lat, "lng": lng}
        if via_admin:
            actor_token = token or self.admin_token
            path = f"/admin/drones/{drone_id}/broken"
        else:
            if not token:
                raise ValueError("token is required for drone self-report broken")
            actor_token = token
            path = f"/drones/{drone_id}/broken"
        return self.api_client.post(path, token=actor_token, json_body=payload, expected_status=expected_status)

    def mark_fixed(
        self,
        drone_id: int,
        *,
        lat: float,
        lng: float,
        token: Optional[str] = None,
        via_admin: bool = True,
        expected_status: int = 200,
    ) -> ApiResult:
        payload = {"lat": lat, "lng": lng}
        if via_admin:
            actor_token = token or self.admin_token
            path = f"/admin/drones/{drone_id}/fixed"
        else:
            if not token:
                raise ValueError("token is required for drone self-fix")
            actor_token = token
            path = f"/drones/{drone_id}/fixed"
        return self.api_client.post(path, token=actor_token, json_body=payload, expected_status=expected_status)

    def list_drones(self, *, token: Optional[str] = None, query: str = "") -> ApiResult:
        actor_token = token or self.admin_token
        path = "/admin/drones"
        if query:
            if not query.startswith("?"):
                query = f"?{query}"
            path = f"{path}{query}"
        return self.api_client.get(path, token=actor_token, expected_status=200)

    def ensure_idle(self, drone_id: int, *, lat: float = 0.0, lng: float = 0.0) -> None:
        """Reset drone to idle via admin fix endpoint."""
        self.mark_fixed(drone_id, lat=lat, lng=lng)
