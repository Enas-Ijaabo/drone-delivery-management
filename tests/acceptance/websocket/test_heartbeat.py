import json

import pytest

from ..support.ws import send_heartbeat, send_multiple_heartbeats, websocket_connection

pytestmark = pytest.mark.acceptance


def test_heartbeat_accepts_valid_coordinates(base_url, drone1_token):
    cases = [
        (31.9454, 35.9284),
        (0.0, 0.0),
        (-31.9, -35.9),
        (-90.0, 0.0),
        (90.0, 0.0),
        (0.0, -180.0),
        (0.0, 180.0),
        (31.945678, 35.928456),
    ]
    for lat, lng in cases:
        response = send_heartbeat(base_url, drone1_token, lat, lng)
        assert response.get("message") == "ok"


def test_heartbeat_missing_fields(base_url, drone1_token):
    response = send_heartbeat(base_url, drone1_token, lat=31.0, lng=35.0)
    assert response.get("message") == "ok"

    with websocket_connection(base_url, drone1_token) as ws:
        ws.send(json.dumps({"type": "heartbeat", "lat": 31.0}))
        error_resp = json.loads(ws.recv())
        assert error_resp.get("message") == "error"


@pytest.mark.parametrize(
    "payload",
    [
        {"lat": 91.0, "lng": 35.0},
        {"lat": -91.0, "lng": 35.0},
        {"lat": 31.0, "lng": 181.0},
        {"lat": 31.0, "lng": -181.0},
    ],
)
def test_heartbeat_rejects_invalid_coordinates(base_url, drone1_token, payload):
    with websocket_connection(base_url, drone1_token) as ws:
        ws.send(json.dumps({"type": "heartbeat", **payload}))
        resp = json.loads(ws.recv())
        assert resp.get("message") == "error"


def test_heartbeat_updates_order_location(
    base_url, order_actions, enduser_token, drone2_token, drone2_id, drone_actions
):
    drone_actions.ensure_idle(drone2_id)
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone2_token)
    response = send_heartbeat(base_url, drone2_token, lat=31.5555, lng=35.6666)
    assert response.get("message") == "ok"
    order = order_actions.get(order_id, token=enduser_token).json()
    assert order["drone_location"]["lat"] == pytest.approx(31.5555, rel=1e-4)
    order_actions.fail(order_id, token=drone2_token)


def test_multiple_heartbeats_work_in_sequence(base_url, drone2_token):
    responses = send_multiple_heartbeats(
        base_url,
        drone2_token,
        [
            {"lat": 31.0, "lng": 35.0},
            {"lat": 32.0, "lng": 36.0},
            {"lat": 33.0, "lng": 37.0},
        ],
    )
    assert all(resp.get("message") == "ok" for resp in responses)
