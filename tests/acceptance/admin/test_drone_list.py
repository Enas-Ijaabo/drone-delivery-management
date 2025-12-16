import pytest

pytestmark = pytest.mark.acceptance


def _list_drones(drone_actions, query=""):
    return drone_actions.list_drones(query=query).json()


def test_drone_list_requires_admin(api_client, admin_token, enduser_token, drone1_token):
    api_client.get("/admin/drones", expected_status=401)
    api_client.get("/admin/drones", token=enduser_token, expected_status=403)
    api_client.get("/admin/drones", token=drone1_token, expected_status=403)
    api_client.get("/admin/drones", token=admin_token, expected_status=200)


def test_drone_list_structure(drone_actions):
    response = _list_drones(drone_actions)
    assert isinstance(response["data"], list)
    assert "meta" in response
    assert response["meta"]["page"] == 1
    assert response["meta"]["page_size"] <= 20


def test_drone_list_pagination(drone_actions):
    page1 = _list_drones(drone_actions, "page=1&page_size=1")
    page2 = _list_drones(drone_actions, "page=2&page_size=1")
    assert len(page1["data"]) == 1
    assert len(page2["data"]) == 1
    assert page1["data"][0]["drone_id"] != page2["data"][0]["drone_id"]


def test_drone_list_pagination_bounds(api_client, admin_token, drone_actions):
    response = _list_drones(drone_actions, "page_size=150")
    assert response["meta"]["page_size"] == 100
    api_client.get("/admin/drones?page=abc", token=admin_token, expected_status=400)
    api_client.get("/admin/drones?page_size=xyz", token=admin_token, expected_status=400)


def test_drone_list_has_next_flag(drone_actions):
    resp = _list_drones(drone_actions, "page=1&page_size=1")
    assert resp["meta"]["has_next"] in (True, False)
    high = _list_drones(drone_actions, "page=999&page_size=20")
    assert high["meta"]["has_next"] is False


def test_drone_list_fields_include_current_order(
    drone_actions, order_actions, enduser_token, drone1_token, drone1_id
):
    drone_actions.ensure_idle(drone1_id)
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    resp = _list_drones(drone_actions, "page_size=100")
    entry = next(item for item in resp["data"] if item["drone_id"] == drone1_id)
    assert entry["current_order_id"] == order_id
    assert entry["status"] in {"reserved", "delivering", "idle"}


def test_drone_list_coordinate_ranges(drone_actions):
    resp = _list_drones(drone_actions, "page_size=5")
    for drone in resp["data"]:
        assert -90 <= drone["lat"] <= 90
        assert -180 <= drone["lng"] <= 180
        if "last_heartbeat" in drone:
            value = drone["last_heartbeat"]
            assert value is None or isinstance(value, str)
