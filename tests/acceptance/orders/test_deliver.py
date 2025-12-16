import pytest

pytestmark = pytest.mark.acceptance


@pytest.fixture(autouse=True)
def _reset_drones(reset_drones):
    return


def _picked_up_order(order_actions, enduser_token, drone_token):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone_token)
    order_actions.pickup(order_id, token=drone_token)
    return order_id


def test_deliver_requires_drone_token(
    api_client, order_actions, enduser_token, admin_token, drone1_token, drone_actions, drone1_id
):
    drone_actions.ensure_idle(drone1_id)
    order_id = _picked_up_order(order_actions, enduser_token, drone1_token)
    api_client.post(f"/orders/{order_id}/deliver", expected_status=401)
    api_client.post(f"/orders/{order_id}/deliver", token="invalid.token", expected_status=401)
    api_client.post(f"/orders/{order_id}/deliver", token=enduser_token, expected_status=403)
    api_client.post(f"/orders/{order_id}/deliver", token=admin_token, expected_status=403)


@pytest.mark.parametrize("order_id", ["abc", "0", "-1"])
def test_deliver_invalid_identifiers(api_client, drone1_token, order_id):
    api_client.post(f"/orders/{order_id}/deliver", token=drone1_token, expected_status=400)


def test_deliver_missing_order(api_client, drone1_token):
    api_client.post("/orders/99999/deliver", token=drone1_token, expected_status=404)


def test_deliver_requires_assigned_drone(order_actions, enduser_token, drone1_token, drone2_token):
    order_id = _picked_up_order(order_actions, enduser_token, drone1_token)
    order_actions.deliver(order_id, token=drone2_token, expected_status=404)


def test_deliver_happy_path(order_actions, enduser_token, drone1_token, drone_actions, drone1_id):
    drone_actions.ensure_idle(drone1_id)
    order_id = _picked_up_order(order_actions, enduser_token, drone1_token)
    result = order_actions.deliver(order_id, token=drone1_token, expected_status=200).json()
    assert result["status"] == "delivered"
    order_actions.deliver(order_id, token=drone1_token, expected_status=409)


def test_deliver_status_transitions(order_actions, enduser_token, drone1_token):
    pending_order = order_actions.create(token=enduser_token)
    order_actions.deliver(pending_order, token=drone1_token, expected_status=404)

    reserved_order = order_actions.create(token=enduser_token)
    order_actions.reserve(reserved_order, token=drone1_token)
    order_actions.deliver(reserved_order, token=drone1_token, expected_status=409)
    order_actions.fail(reserved_order, token=drone1_token)

    canceled_order = order_actions.create(token=enduser_token)
    order_actions.cancel(canceled_order, token=enduser_token)
    order_actions.deliver(canceled_order, token=drone1_token, expected_status=404)

    failed_order = _picked_up_order(order_actions, enduser_token, drone1_token)
    order_actions.fail(failed_order, token=drone1_token)
    order_actions.deliver(failed_order, token=drone1_token, expected_status=409)
