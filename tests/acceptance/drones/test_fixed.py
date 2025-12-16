import pytest

pytestmark = pytest.mark.acceptance


def test_admin_fixes_broken_drone(drone_actions, drone1_id, drone1_token):
    drone_actions.mark_broken(drone1_id, lat=30.5, lng=35.5, token=drone1_token, via_admin=False)
    body = drone_actions.mark_fixed(drone1_id, lat=30.0, lng=35.0, via_admin=True).json()
    assert body["status"] == "idle"
    updated = drone_actions.mark_fixed(drone1_id, lat=30.1, lng=35.1, via_admin=True).json()
    assert updated["lat"] == pytest.approx(30.1)


def test_fix_idempotent(drone_actions, drone1_id):
    body = drone_actions.mark_fixed(drone1_id, lat=30.2, lng=35.2, via_admin=True).json()
    assert body["status"] == "idle"


def test_drone_self_fix(drone_actions, drone2_id, drone2_token):
    drone_actions.mark_broken(drone2_id, lat=29.5, lng=34.5, token=drone2_token, via_admin=False)
    body = drone_actions.mark_fixed(
        drone2_id, lat=29.0, lng=34.0, token=drone2_token, via_admin=False
    ).json()
    assert body["status"] == "idle"


def test_drone_cannot_fix_other(drone_actions, drone2_id, drone1_token):
    drone_actions.mark_broken(drone2_id, lat=29.5, lng=34.5, via_admin=True)
    drone_actions.mark_fixed(
        drone2_id,
        lat=29.0,
        lng=34.0,
        token=drone1_token,
        via_admin=False,
        expected_status=403,
    )
    drone_actions.ensure_idle(drone2_id, lat=29.0, lng=34.0)


def test_enduser_cannot_fix_drone(api_client, drone1_id, enduser_token):
    api_client.post(
        f"/drones/{drone1_id}/fixed",
        token=enduser_token,
        json_body={"lat": 30.0, "lng": 35.0},
        expected_status=403,
    )
    api_client.post(
        f"/admin/drones/{drone1_id}/fixed",
        token=enduser_token,
        json_body={"lat": 30.0, "lng": 35.0},
        expected_status=403,
    )


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({}, id="empty"),
        pytest.param({"lat": 999, "lng": 35}, id="lat-invalid"),
        pytest.param({"lat": 30, "lng": 999}, id="lng-invalid"),
    ],
)
def test_fix_requires_lat_lng(api_client, admin_token, drone1_id, payload):
    api_client.post(
        f"/admin/drones/{drone1_id}/fixed",
        token=admin_token,
        json_body=payload,
        expected_status=400,
    )


def test_fix_releases_active_order(
    drone_actions, order_actions, enduser_token, drone1_token, drone1_id
):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    drone_actions.mark_broken(drone1_id, lat=30.05, lng=35.05, token=drone1_token, via_admin=False)
    body = drone_actions.mark_fixed(drone1_id, lat=30.0, lng=35.0, via_admin=True).json()
    assert body["status"] == "idle"
    order = order_actions.get(order_id, token=enduser_token).json()
    assert order["status"] == "pending"


def test_fixed_drone_can_accept_orders(
    drone_actions, order_actions, enduser_token, drone2_token, drone2_id
):
    order_id = order_actions.create(token=enduser_token)
    drone_actions.mark_broken(drone2_id, lat=29.5, lng=34.5, token=drone2_token, via_admin=False)
    order_actions.reserve(order_id, token=drone2_token, expected_status=409)
    drone_actions.mark_fixed(drone2_id, lat=29.0, lng=34.0, via_admin=True)
    order_actions.reserve(order_id, token=drone2_token, expected_status=200)
    order_actions.fail(order_id, token=drone2_token)


def test_multiple_fix_break_cycles(drone_actions, drone1_id, drone1_token):
    for lat in (30.5, 30.6):
        drone_actions.mark_broken(drone1_id, lat=lat, lng=35.5, token=drone1_token, via_admin=False)
        body = drone_actions.mark_fixed(drone1_id, lat=30.0, lng=35.0, via_admin=True).json()
        assert body["status"] == "idle"


def test_fix_response_fields(drone_actions, drone1_id, drone1_token):
    drone_actions.mark_broken(drone1_id, lat=30.5, lng=35.5, token=drone1_token, via_admin=False)
    body = drone_actions.mark_fixed(drone1_id, lat=30.0, lng=35.0, via_admin=True).json()
    assert body["drone_id"] == drone1_id
    assert body["status"] == "idle"
    assert body["lat"] == pytest.approx(30.0)
    assert body["lng"] == pytest.approx(35.0)
