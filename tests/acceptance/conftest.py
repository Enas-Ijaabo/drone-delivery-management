import os
import time
from typing import Dict, Tuple

import pytest
import requests

from .support.actions import DroneActions, OrderActions
from .support.http import ApiClient


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--base-url",
        action="store",
        default=None,
        help="Override base URL for acceptance tests (default: env BASE_URL or http://localhost:8080)",
    )


@pytest.fixture(scope="session")
def base_url(pytestconfig: pytest.Config) -> str:
    cli_value = pytestconfig.getoption("base_url")
    env_value = os.getenv("BASE_URL")
    return (cli_value or env_value or "http://localhost:8080").rstrip("/")


@pytest.fixture(scope="session")
def api_client(base_url: str) -> ApiClient:
    client = ApiClient(base_url)
    yield client
    client.close()


@pytest.fixture(scope="session")
def auth_response_factory(api_client: ApiClient):
    cache: Dict[Tuple[str, str], Dict] = {}

    def _factory(username: str, password: str = "password") -> Dict:
        key = (username, password)
        if key not in cache:
            result = api_client.post(
                "/auth/token",
                json_body={"name": username, "password": password},
                expected_status=200,
            )
            cache[key] = result.json()
        return cache[key]

    return _factory


@pytest.fixture(scope="session")
def token_factory(auth_response_factory):
    def _token(username: str, password: str = "password") -> str:
        return auth_response_factory(username, password)["access_token"]

    return _token


@pytest.fixture(scope="session")
def admin_token(token_factory) -> str:
    return token_factory("admin")


@pytest.fixture(scope="session")
def enduser_token(token_factory) -> str:
    return token_factory("enduser1")


@pytest.fixture(scope="session")
def enduser2_token(token_factory) -> str:
    return token_factory("enduser2")


@pytest.fixture(scope="session")
def drone1_token(token_factory) -> str:
    return token_factory("drone1")


@pytest.fixture(scope="session")
def drone2_token(token_factory) -> str:
    return token_factory("drone2")


@pytest.fixture(scope="session")
def drone_token(drone1_token: str) -> str:
    """Backward-compatible alias for the default drone token fixture."""
    return drone1_token


@pytest.fixture(scope="session")
def admin_profile(auth_response_factory) -> Dict:
    return auth_response_factory("admin")


@pytest.fixture(scope="session")
def enduser_profile(auth_response_factory) -> Dict:
    return auth_response_factory("enduser1")


@pytest.fixture(scope="session")
def enduser_id(enduser_profile) -> int:
    return enduser_profile["user"]["id"]


@pytest.fixture(scope="session")
def enduser2_profile(auth_response_factory) -> Dict:
    return auth_response_factory("enduser2")


@pytest.fixture(scope="session")
def enduser2_id(enduser2_profile) -> int:
    return enduser2_profile["user"]["id"]


@pytest.fixture(scope="session")
def drone1_profile(auth_response_factory) -> Dict:
    return auth_response_factory("drone1")


@pytest.fixture(scope="session")
def drone2_profile(auth_response_factory) -> Dict:
    return auth_response_factory("drone2")


@pytest.fixture(scope="session")
def drone1_id(drone1_profile) -> int:
    return drone1_profile["user"]["id"]


@pytest.fixture(scope="session")
def drone2_id(drone2_profile) -> int:
    return drone2_profile["user"]["id"]


@pytest.fixture(scope="session", autouse=True)
def wait_for_api(base_url: str) -> None:
    """Poll the health endpoint so dockerized runs can wait for the API."""
    timeout = int(os.getenv("API_WAIT_TIMEOUT", "60"))
    deadline = time.time() + timeout
    health_url = f"{base_url}/health"

    while time.time() < deadline:
        try:
            resp = requests.get(health_url, timeout=2)
            if resp.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(1)

    pytest.fail(f"API at {base_url} did not become healthy within {timeout} seconds.")


@pytest.fixture
def order_factory(api_client: ApiClient, enduser_token: str):
    """Create orders for acceptance tests; defaults to enduser1 credentials."""

    def _create(
        *,
        token: str = enduser_token,
        pickup_lat: float = 31.9454,
        pickup_lng: float = 35.9284,
        dropoff_lat: float = 31.9632,
        dropoff_lng: float = 35.9106,
    ) -> int:
        result = api_client.post(
            "/orders",
            token=token,
            json_body={
                "pickup_lat": pickup_lat,
                "pickup_lng": pickup_lng,
                "dropoff_lat": dropoff_lat,
                "dropoff_lng": dropoff_lng,
            },
            expected_status=201,
        )
        body = result.json()
        assert "order_id" in body, "Order creation response missing order_id"
        return body["order_id"]

    return _create


@pytest.fixture
def order_actions(api_client: ApiClient) -> OrderActions:
    return OrderActions(api_client)


@pytest.fixture(scope="session")
def drone_actions(api_client: ApiClient, admin_token: str) -> DroneActions:
    return DroneActions(api_client=api_client, admin_token=admin_token)


@pytest.fixture
def reset_drones(drone_actions: DroneActions, drone1_id: int, drone2_id: int):
    drone_actions.ensure_idle(drone1_id)
    drone_actions.ensure_idle(drone2_id)
    yield
    drone_actions.ensure_idle(drone1_id)
    drone_actions.ensure_idle(drone2_id)
