import pytest

pytestmark = pytest.mark.acceptance


@pytest.fixture(autouse=True)
def _reset_drones(reset_drones):
    return


def test_happy_path(order_actions, enduser_token, drone1_token, drone_actions, drone1_id):
    drone_actions.ensure_idle(drone1_id)
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token, expected_status=200)
    order_actions.pickup(order_id, token=drone1_token, expected_status=200)
    body = order_actions.deliver(order_id, token=drone1_token, expected_status=200).json()
    assert body["status"] == "delivered"


def test_failure_after_pickup(order_actions, enduser_token, drone1_token):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    order_actions.pickup(order_id, token=drone1_token)
    body = order_actions.fail(order_id, token=drone1_token, expected_status=200).json()
    assert body["status"] == "failed"


def test_failure_after_reserve(order_actions, enduser_token, drone1_token):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    body = order_actions.fail(order_id, token=drone1_token, expected_status=200).json()
    assert body["status"] == "failed"


def test_cancel_before_reserve(order_actions, enduser_token, drone1_token):
    order_id = order_actions.create(token=enduser_token)
    order_actions.cancel(order_id, token=enduser_token, expected_status=200)
    order_actions.reserve(order_id, token=drone1_token, expected_status=409)


def test_sequential_orders(order_actions, enduser_token, drone1_token):
    first_order = order_actions.create(token=enduser_token)
    second_order = order_actions.create(token=enduser_token)

    order_actions.reserve(first_order, token=drone1_token)
    order_actions.pickup(first_order, token=drone1_token)
    order_actions.deliver(first_order, token=drone1_token)

    order_actions.reserve(second_order, token=drone1_token, expected_status=200)
