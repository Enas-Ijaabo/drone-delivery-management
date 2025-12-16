import pytest

pytestmark = pytest.mark.acceptance


def test_get_order_requires_valid_token(api_client, order_factory):
    order_id = order_factory()
    api_client.get(f"/orders/{order_id}", token="invalid.token", expected_status=401)


def test_get_order_forbidden_for_other_user(api_client, order_factory, enduser_token, enduser2_token):
    other_order = order_factory(token=enduser2_token)
    api_client.get(f"/orders/{other_order}", token=enduser_token, expected_status=403)


@pytest.mark.parametrize("order_id", ["abc", "0", "-1"])
def test_get_order_rejects_invalid_identifiers(api_client, enduser_token, order_id):
    api_client.get(f"/orders/{order_id}", token=enduser_token, expected_status=400)


def test_get_order_missing_returns_not_found(api_client, enduser_token):
    api_client.get("/orders/99999", token=enduser_token, expected_status=404)


def test_get_pending_order_fields(api_client, order_factory, enduser_token):
    order_id = order_factory()
    result = api_client.get(f"/orders/{order_id}", token=enduser_token, expected_status=200)
    body = result.json()

    assert body["status"] == "pending"
    assert body["order_id"] == order_id
    assert "pickup" in body and "dropoff" in body
    assert not body.get("assigned_drone_id")
    assert body.get("drone_location") in (None, {})
    assert body.get("eta_minutes") is None


def test_get_order_lifecycle_updates_fields(api_client, order_factory, enduser_token, drone_token):
    order_id = order_factory()

    # Reserve the order
    api_client.post(f"/orders/{order_id}/reserve", token=drone_token, expected_status=200)
    reserved = api_client.get(f"/orders/{order_id}", token=enduser_token, expected_status=200).json()
    assert reserved["status"] == "reserved"
    assert reserved.get("assigned_drone_id")
    assert isinstance(reserved.get("drone_location"), dict)
    assert reserved.get("eta_minutes") is not None

    # Pick up the order
    api_client.post(f"/orders/{order_id}/pickup", token=drone_token, expected_status=200)
    picked_up = api_client.get(f"/orders/{order_id}", token=enduser_token, expected_status=200).json()
    assert picked_up["status"] == "picked_up"
    assert isinstance(picked_up.get("drone_location"), dict)
    assert picked_up.get("eta_minutes") is not None

    # Deliver the order
    api_client.post(f"/orders/{order_id}/deliver", token=drone_token, expected_status=200)
    delivered = api_client.get(f"/orders/{order_id}", token=enduser_token, expected_status=200).json()
    assert delivered["status"] == "delivered"
