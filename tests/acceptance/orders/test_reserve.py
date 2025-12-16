import pytest

pytestmark = pytest.mark.acceptance


@pytest.fixture(autouse=True)
def _reset_drones(reset_drones):
    """Ensure drones are idle before each reserve test."""
    return


def test_reserve_requires_drone_token(
    api_client, order_actions, admin_token, enduser_token, drone1_token, drone_actions, drone1_id
):
    drone_actions.ensure_idle(drone1_id)
    order_id = order_actions.create(token=enduser_token)
    api_client.post(f"/orders/{order_id}/reserve", expected_status=401)
    api_client.post(f"/orders/{order_id}/reserve", token="invalid.token", expected_status=401)
    api_client.post(f"/orders/{order_id}/reserve", token=enduser_token, expected_status=403)
    api_client.post(f"/orders/{order_id}/reserve", token=admin_token, expected_status=403)
    order_actions.reserve(order_id, token=drone1_token, expected_status=200)


@pytest.mark.parametrize("order_id", ["abc", "0", "-1"])
def test_reserve_invalid_identifiers(api_client, drone1_token, order_id):
    api_client.post(f"/orders/{order_id}/reserve", token=drone1_token, expected_status=400)


def test_reserve_missing_order(api_client, drone1_token):
    api_client.post("/orders/999999/reserve", token=drone1_token, expected_status=404)


def test_reserve_pending_order(order_actions, drone1_token, drone_actions, drone1_id, enduser_token):
    drone_actions.ensure_idle(drone1_id)
    order_id = order_actions.create(token=enduser_token)
    result = order_actions.reserve(order_id, token=drone1_token, expected_status=200).json()
    assert result["status"] == "reserved"
    order_actions.reserve(order_id, token=drone1_token, expected_status=409)


def test_reserve_prevents_other_statuses(
    order_actions, enduser_token, drone1_token, drone2_token, drone_actions, drone1_id, drone2_id
):
    drone_actions.ensure_idle(drone1_id)
    drone_actions.ensure_idle(drone2_id)

    canceled_order = order_actions.create(token=enduser_token)
    order_actions.cancel(canceled_order, token=enduser_token)
    order_actions.reserve(canceled_order, token=drone1_token, expected_status=409)

    delivered_order = order_actions.create(token=enduser_token)
    order_actions.reserve(delivered_order, token=drone1_token)
    order_actions.pickup(delivered_order, token=drone1_token)
    order_actions.deliver(delivered_order, token=drone1_token)
    order_actions.reserve(delivered_order, token=drone1_token, expected_status=409)

    failed_order = order_actions.create(token=enduser_token)
    order_actions.reserve(failed_order, token=drone1_token)
    order_actions.fail(failed_order, token=drone1_token)
    order_actions.reserve(failed_order, token=drone1_token, expected_status=409)

    picked_up_order = order_actions.create(token=enduser_token)
    order_actions.reserve(picked_up_order, token=drone1_token)
    order_actions.pickup(picked_up_order, token=drone1_token)
    order_actions.reserve(picked_up_order, token=drone2_token, expected_status=409)
