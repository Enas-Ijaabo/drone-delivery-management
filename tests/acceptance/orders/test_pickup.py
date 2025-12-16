import pytest

pytestmark = pytest.mark.acceptance


@pytest.fixture(autouse=True)
def _reset_drones(reset_drones):
    return


def _reserve_order(order_actions, enduser_token, drone_token):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone_token)
    return order_id


def test_pickup_requires_drone_token(
    api_client, order_actions, enduser_token, admin_token, drone1_token, drone_actions, drone1_id
):
    drone_actions.ensure_idle(drone1_id)
    order_id = _reserve_order(order_actions, enduser_token, drone1_token)
    api_client.post(f"/orders/{order_id}/pickup", expected_status=401)
    api_client.post(f"/orders/{order_id}/pickup", token="invalid.token", expected_status=401)
    api_client.post(f"/orders/{order_id}/pickup", token=enduser_token, expected_status=403)
    api_client.post(f"/orders/{order_id}/pickup", token=admin_token, expected_status=403)


@pytest.mark.parametrize("order_id", ["abc", "0", "-1"])
def test_pickup_invalid_identifiers(api_client, drone1_token, order_id):
    api_client.post(f"/orders/{order_id}/pickup", token=drone1_token, expected_status=400)


def test_pickup_missing_order(api_client, drone1_token):
    api_client.post("/orders/99999/pickup", token=drone1_token, expected_status=404)


def test_pickup_requires_assigned_drone(order_actions, enduser_token, drone1_token, drone2_token):
    order_id = _reserve_order(order_actions, enduser_token, drone1_token)
    order_actions.pickup(order_id, token=drone2_token, expected_status=404)


def test_pickup_reserved_order(order_actions, enduser_token, drone1_token, drone_actions, drone1_id):
    drone_actions.ensure_idle(drone1_id)
    order_id = _reserve_order(order_actions, enduser_token, drone1_token)
    body = order_actions.pickup(order_id, token=drone1_token, expected_status=200).json()
    assert body["status"] == "picked_up"
    order_actions.pickup(order_id, token=drone1_token, expected_status=409)


def test_pickup_status_transitions(order_actions, enduser_token, drone1_token):
    pending_order = order_actions.create(token=enduser_token)
    order_actions.pickup(pending_order, token=drone1_token, expected_status=404)

    delivered_order = _reserve_order(order_actions, enduser_token, drone1_token)
    order_actions.pickup(delivered_order, token=drone1_token)
    order_actions.deliver(delivered_order, token=drone1_token)
    order_actions.pickup(delivered_order, token=drone1_token, expected_status=409)

    canceled_order = order_actions.create(token=enduser_token)
    order_actions.cancel(canceled_order, token=enduser_token)
    order_actions.pickup(canceled_order, token=drone1_token, expected_status=404)

    failed_order = _reserve_order(order_actions, enduser_token, drone1_token)
    order_actions.pickup(failed_order, token=drone1_token)
    order_actions.fail(failed_order, token=drone1_token)
    order_actions.pickup(failed_order, token=drone1_token, expected_status=409)
