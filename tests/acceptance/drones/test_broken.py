import pytest

pytestmark = pytest.mark.acceptance


def test_drone_self_reports_broken(drone_actions, drone1_id, drone1_token):
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)
    body = drone_actions.mark_broken(
        drone1_id, lat=30.5, lng=35.5, token=drone1_token, via_admin=False, expected_status=200
    ).json()
    assert body["status"] == "broken"
    updated = drone_actions.mark_broken(
        drone1_id, lat=30.7, lng=35.7, token=drone1_token, via_admin=False, expected_status=200
    ).json()
    assert updated["lat"] == pytest.approx(30.7)
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)


def test_drone_cannot_mark_other_drone_broken(drone_actions, drone2_id, drone1_token):
    drone_actions.mark_broken(
        drone2_id,
        lat=29.5,
        lng=34.5,
        token=drone1_token,
        via_admin=False,
        expected_status=403,
    )


def test_admin_can_mark_drone_broken(drone_actions, drone2_id):
    body = drone_actions.mark_broken(
        drone2_id, lat=29.5, lng=34.5, via_admin=True, expected_status=200
    ).json()
    assert body["status"] == "broken"
    drone_actions.ensure_idle(drone2_id, lat=29.0, lng=34.0)


def test_broken_drone_triggers_handoff(drone_actions, order_actions, enduser_token, drone1_token, drone1_id):
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    order_actions.pickup(order_id, token=drone1_token)

    drone_actions.mark_broken(drone1_id, lat=30.05, lng=35.05, token=drone1_token, via_admin=False)
    order = order_actions.get(order_id, token=enduser_token).json()
    assert order["status"] in {"handoff_pending", "pending"}
    assert order.get("handoff_lat") is not None
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)


def test_admin_marks_busy_drone_broken_releases_order(
    drone_actions, order_actions, enduser_token, drone2_token, drone2_id, admin_token
):
    drone_actions.ensure_idle(drone2_id, lat=29.0, lng=34.0)
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone2_token)
    drone_actions.mark_broken(drone2_id, lat=29.55, lng=34.55, via_admin=True)
    order = order_actions.get(order_id, token=enduser_token).json()
    assert order["status"] == "pending"
    drone_actions.ensure_idle(drone2_id, lat=29.0, lng=34.0)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({}, id="empty"),
        pytest.param({"lat": 999, "lng": 35}, id="lat-invalid"),
        pytest.param({"lat": 30, "lng": 999}, id="lng-invalid"),
    ],
)
def test_broken_requires_lat_lng(api_client, drone1_token, drone1_id, payload):
    api_client.post(
        f"/drones/{drone1_id}/broken",
        token=drone1_token,
        json_body=payload,
        expected_status=400,
    )


def test_broken_authorization(api_client, drone1_id, enduser_token):
    api_client.post(
        f"/drones/{drone1_id}/broken",
        token=enduser_token,
        json_body={"lat": 30, "lng": 35},
        expected_status=403,
    )
    api_client.post(
        f"/admin/drones/{drone1_id}/broken",
        token=enduser_token,
        json_body={"lat": 30, "lng": 35},
        expected_status=403,
    )
