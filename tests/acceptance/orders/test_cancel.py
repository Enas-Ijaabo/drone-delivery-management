import pytest

pytestmark = pytest.mark.acceptance


def test_cancel_requires_auth(api_client, order_actions, admin_token, enduser_token):
    order_id = order_actions.create(token=enduser_token)
    api_client.post(f"/orders/{order_id}/cancel", expected_status=401)
    api_client.post(f"/orders/{order_id}/cancel", token="invalid.token", expected_status=401)
    api_client.post(f"/orders/{order_id}/cancel", token=admin_token, expected_status=403)


def test_cancel_pending_order(order_actions, enduser_token):
    order_id = order_actions.create(token=enduser_token)
    result = order_actions.cancel(order_id, token=enduser_token, expected_status=200)
    body = result.json()
    assert body["status"] == "canceled"
    assert body["canceled_at"] is not None
    order_actions.cancel(order_id, token=enduser_token, expected_status=409)


def test_cancel_enforces_ownership(order_actions, enduser_token, enduser2_token):
    other_order = order_actions.create(token=enduser2_token)
    order_actions.cancel(other_order, token=enduser_token, expected_status=403)


@pytest.mark.parametrize("order_id", ["abc", "0", "-1"])
def test_cancel_invalid_identifiers(api_client, enduser_token, order_id):
    api_client.post(f"/orders/{order_id}/cancel", token=enduser_token, expected_status=400)


def test_cancel_missing_order(order_actions, enduser_token):
    api_client = order_actions.api_client
    api_client.post("/orders/99999/cancel", token=enduser_token, expected_status=404)
