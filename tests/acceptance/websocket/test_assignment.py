import concurrent.futures
import time

import pytest

from ..support.ws import send_assignment_ack, send_heartbeat, wait_for_assignment

pytestmark = pytest.mark.acceptance


def _set_drone_location(base_url, token, lat, lng):
    response = send_heartbeat(base_url, token, lat, lng)
    assert response.get("message") == "ok"


def test_assignment_notification(base_url, order_actions, enduser_token, drone1_token, drone1_id, drone_actions):
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)
    _set_drone_location(base_url, drone1_token, 30.0, 35.0)

    with concurrent.futures.ThreadPoolExecutor() as executor:
        future = executor.submit(wait_for_assignment, base_url, drone1_token, 15)
        time.sleep(1)
        order_id = order_actions.create(token=enduser_token)
        assignment = future.result(timeout=20)

    assert assignment["order_id"] == order_id
    ack = send_assignment_ack(base_url, drone1_token, order_id, "accepted")
    assert ack.get("message") == "acknowledged"
    order_actions.reserve(order_id, token=drone1_token)
    order_actions.fail(order_id, token=drone1_token)


def test_far_order_stays_pending(base_url, order_actions, enduser_token, drone1_token, drone1_id, drone_actions):
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)
    _set_drone_location(base_url, drone1_token, 30.0, 35.0)
    far_order = order_actions.create(
        token=enduser_token, pickup_lat=60.0, pickup_lng=60.0, dropoff_lat=60.1, dropoff_lng=60.1
    )
    time.sleep(1)
    order = order_actions.get(far_order, token=enduser_token).json()
    assert order["status"] == "pending"
    assert order.get("assigned_drone_id") is None


def test_nearest_drone_receives_assignment(
    base_url,
    order_actions,
    enduser_token,
    drone1_token,
    drone2_token,
    drone1_id,
    drone2_id,
    drone_actions,
):
    drone_actions.ensure_idle(drone1_id, lat=30.0, lng=35.0)
    drone_actions.ensure_idle(drone2_id, lat=32.0, lng=37.0)
    _set_drone_location(base_url, drone1_token, 30.0, 35.0)
    _set_drone_location(base_url, drone2_token, 32.0, 37.0)

    with concurrent.futures.ThreadPoolExecutor() as executor:
        future = executor.submit(wait_for_assignment, base_url, drone1_token, 10)
        time.sleep(1)
        order_id = order_actions.create(token=enduser_token, pickup_lat=30.1, pickup_lng=35.1)
        assignment = future.result(timeout=15)

    assert assignment["order_id"] == order_id
    assert assignment.get("drone_id") == drone1_id
    order_actions.reserve(order_id, token=drone1_token)
    order_actions.fail(order_id, token=drone1_token)
