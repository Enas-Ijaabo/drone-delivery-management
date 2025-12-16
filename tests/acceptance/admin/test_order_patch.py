import pytest

pytestmark = pytest.mark.acceptance


def _patch_order(api_client, admin_token, order_id, payload, expected_status=200):
    return api_client.patch(
        f"/admin/orders/{order_id}",
        token=admin_token,
        json_body=payload,
        expected_status=expected_status,
    )


def test_admin_updates_pickup_and_dropoff(api_client, admin_token, order_actions, enduser_token):
    order_id = order_actions.create(token=enduser_token)
    payload = {"pickup_lat": 30.5, "pickup_lng": 35.5}
    body = _patch_order(api_client, admin_token, order_id, payload).json()
    assert body["pickup"]["lat"] == pytest.approx(30.5)
    assert body["pickup"]["lng"] == pytest.approx(35.5)

    payload = {"dropoff_lat": 31.5, "dropoff_lng": 36.5}
    body = _patch_order(api_client, admin_token, order_id, payload).json()
    assert body["dropoff"]["lat"] == pytest.approx(31.5)
    assert body["dropoff"]["lng"] == pytest.approx(36.5)


def test_admin_updates_both_coordinates(api_client, admin_token, order_actions, enduser_token):
    order_id = order_actions.create(token=enduser_token)
    payload = {
        "pickup_lat": 30.7,
        "pickup_lng": 35.7,
        "dropoff_lat": 31.7,
        "dropoff_lng": 36.7,
    }
    body = _patch_order(api_client, admin_token, order_id, payload).json()
    assert body["pickup"]["lat"] == pytest.approx(30.7)
    assert body["dropoff"]["lng"] == pytest.approx(36.7)


def test_admin_route_update_only_pending(
    api_client,
    admin_token,
    order_actions,
    enduser_token,
    drone1_token,
    drone_actions,
    drone1_id,
    drone2_token,
    drone2_id,
):
    drone_actions.ensure_idle(drone1_id)
    drone_actions.ensure_idle(drone2_id)
    reserved = order_actions.create(token=enduser_token)
    order_actions.reserve(reserved, token=drone1_token)
    _patch_order(api_client, admin_token, reserved, {"pickup_lat": 30.0, "pickup_lng": 35.0}, expected_status=409)
    order_actions.fail(reserved, token=drone1_token)

    picked_up = order_actions.create(token=enduser_token)
    order_actions.reserve(picked_up, token=drone2_token)
    order_actions.pickup(picked_up, token=drone2_token)
    _patch_order(api_client, admin_token, picked_up, {"pickup_lat": 30.0, "pickup_lng": 35.0}, expected_status=409)
    order_actions.deliver(picked_up, token=drone2_token)

    delivered = order_actions.create(token=enduser_token)
    order_actions.reserve(delivered, token=drone1_token)
    order_actions.pickup(delivered, token=drone1_token)
    order_actions.deliver(delivered, token=drone1_token)
    _patch_order(api_client, admin_token, delivered, {"pickup_lat": 30.0, "pickup_lng": 35.0}, expected_status=409)

    canceled = order_actions.create(token=enduser_token)
    order_actions.cancel(canceled, token=enduser_token)
    _patch_order(api_client, admin_token, canceled, {"pickup_lat": 30.0, "pickup_lng": 35.0}, expected_status=409)

    failed = order_actions.create(token=enduser_token)
    order_actions.reserve(failed, token=drone1_token)
    order_actions.fail(failed, token=drone1_token)
    _patch_order(api_client, admin_token, failed, {"pickup_lat": 30.0, "pickup_lng": 35.0}, expected_status=409)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({}, id="empty"),
        pytest.param({"pickup_lat": 30.5}, id="pickup-lat-only"),
        pytest.param({"pickup_lng": 35.5}, id="pickup-lng-only"),
        pytest.param({"dropoff_lat": 31.5}, id="dropoff-lat-only"),
        pytest.param({"dropoff_lng": 36.5}, id="dropoff-lng-only"),
    ],
)
def test_admin_route_update_requires_full_pairs(api_client, admin_token, order_actions, enduser_token, payload):
    order_id = order_actions.create(token=enduser_token)
    _patch_order(api_client, admin_token, order_id, payload, expected_status=400)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({"pickup_lat": 91, "pickup_lng": 35}, id="pickup-lat-high"),
        pytest.param({"pickup_lat": -91, "pickup_lng": 35}, id="pickup-lat-low"),
        pytest.param({"pickup_lat": 30, "pickup_lng": 181}, id="pickup-lng-high"),
        pytest.param({"pickup_lat": 30, "pickup_lng": -181}, id="pickup-lng-low"),
        pytest.param({"dropoff_lat": 95, "dropoff_lng": 36}, id="dropoff-lat-high"),
        pytest.param({"dropoff_lat": 31, "dropoff_lng": 200}, id="dropoff-lng-high"),
    ],
)
def test_admin_route_update_invalid_coordinates(
    api_client, admin_token, order_actions, enduser_token, payload
):
    order_id = order_actions.create(token=enduser_token)
    _patch_order(api_client, admin_token, order_id, payload, expected_status=400)


def test_admin_route_update_authorization(api_client, admin_token, enduser_token, drone1_token, order_actions):
    order_id = order_actions.create(token=enduser_token)
    payload = {"pickup_lat": 30.5, "pickup_lng": 35.5}
    api_client.patch(f"/admin/orders/{order_id}", json_body=payload, expected_status=401)
    api_client.patch(f"/admin/orders/{order_id}", token=enduser_token, json_body=payload, expected_status=403)
    api_client.patch(f"/admin/orders/{order_id}", token=drone1_token, json_body=payload, expected_status=403)


def test_admin_route_update_invalid_ids(api_client, admin_token):
    payload = {"pickup_lat": 30.5, "pickup_lng": 35.5}
    api_client.patch("/admin/orders/999999", token=admin_token, json_body=payload, expected_status=404)
    api_client.patch("/admin/orders/abc", token=admin_token, json_body=payload, expected_status=400)
    api_client.patch("/admin/orders/0", token=admin_token, json_body=payload, expected_status=400)
    api_client.patch("/admin/orders/-1", token=admin_token, json_body=payload, expected_status=400)


def test_admin_route_update_response_fields(api_client, admin_token, order_actions, enduser_token):
    order_id = order_actions.create(token=enduser_token)
    payload = {"pickup_lat": 30.8, "pickup_lng": 35.8}
    body = _patch_order(api_client, admin_token, order_id, payload).json()
    assert body["order_id"] == order_id
    assert body["status"] == "pending"
    assert body["pickup"]["lat"] == pytest.approx(30.8)
    assert "created_at" in body and "updated_at" in body
