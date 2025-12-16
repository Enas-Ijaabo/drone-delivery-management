from urllib.parse import urlencode

import pytest

pytestmark = pytest.mark.acceptance


@pytest.fixture
def idle_drone1(drone_actions, drone1_id):
    drone_actions.ensure_idle(drone1_id)
    yield
    drone_actions.ensure_idle(drone1_id)


def _list_orders(api_client, admin_token, **params):
    query = f"?{urlencode(params)}" if params else ""
    return api_client.get(f"/admin/orders{query}", token=admin_token, expected_status=200).json()


def _order_ids(response):
    return [item["order_id"] for item in response["data"]]


def test_admin_order_list_requires_admin(api_client, admin_token, enduser_token, drone1_token):
    api_client.get("/admin/orders", expected_status=401)
    api_client.get("/admin/orders", token=enduser_token, expected_status=403)
    api_client.get("/admin/orders", token=drone1_token, expected_status=403)
    api_client.get("/admin/orders", token=admin_token, expected_status=200)


def test_admin_order_list_structure(api_client, admin_token, order_actions, enduser_token):
    ids = [order_actions.create(token=enduser_token) for _ in range(3)]
    response = _list_orders(api_client, admin_token)
    assert "data" in response and isinstance(response["data"], list)
    assert "meta" in response
    returned_ids = _order_ids(response)
    assert any(order_id in returned_ids for order_id in ids)
    assert response["meta"]["page"] == 1
    assert response["meta"]["page_size"] <= 20
    assert "has_next" in response["meta"]


def test_admin_order_list_pagination(api_client, admin_token):
    single = _list_orders(api_client, admin_token, page_size=1)
    assert len(single["data"]) == 1
    assert single["meta"]["page_size"] == 1
    page_two = _list_orders(api_client, admin_token, page=2, page_size=1)
    assert page_two["meta"]["page"] == 2


def test_admin_order_list_invalid_pagination(api_client, admin_token):
    negative_page = _list_orders(api_client, admin_token, page=-1)
    assert negative_page["meta"]["page"] == 1
    negative_size = _list_orders(api_client, admin_token, page_size=-5)
    assert negative_size["meta"]["page_size"] == 20
    api_client.get("/admin/orders?page=abc", token=admin_token, expected_status=400)
    api_client.get("/admin/orders?page_size=xyz", token=admin_token, expected_status=400)


def test_admin_order_list_filter_by_status(
    api_client, admin_token, order_actions, enduser_token, drone1_token, idle_drone1
):
    pending_order = order_actions.create(token=enduser_token)
    reserved_order = order_actions.create(token=enduser_token)
    order_actions.reserve(reserved_order, token=drone1_token)

    pending_resp = _list_orders(api_client, admin_token, status="pending")
    assert pending_order in _order_ids(pending_resp)

    reserved_resp = _list_orders(api_client, admin_token, status="reserved")
    assert reserved_order in _order_ids(reserved_resp)

    api_client.get("/admin/orders?status=invalid", token=admin_token, expected_status=400)


def test_admin_order_list_filter_by_enduser(
    api_client, admin_token, order_actions, enduser_token, enduser2_token, enduser_id, enduser2_id
):
    order1 = order_actions.create(token=enduser_token)
    order2 = order_actions.create(token=enduser2_token)

    user1_resp = _list_orders(api_client, admin_token, enduser_id=enduser_id)
    assert order1 in _order_ids(user1_resp)
    assert order2 not in _order_ids(user1_resp)

    user2_resp = _list_orders(api_client, admin_token, enduser_id=enduser2_id)
    assert order2 in _order_ids(user2_resp)

    api_client.get("/admin/orders?enduser_id=abc", token=admin_token, expected_status=400)
    api_client.get("/admin/orders?enduser_id=-1", token=admin_token, expected_status=400)


def test_admin_order_list_filter_by_assigned_drone(
    api_client, admin_token, order_actions, enduser_token, drone1_token, drone1_id, idle_drone1
):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)

    resp = _list_orders(api_client, admin_token, assigned_drone_id=drone1_id)
    assert order_id in _order_ids(resp)
    api_client.get("/admin/orders?assigned_drone_id=xyz", token=admin_token, expected_status=400)


def test_admin_order_list_combined_filters(
    api_client, admin_token, order_actions, enduser_token, drone1_token, enduser_id, drone1_id, idle_drone1
):
    order_id = order_actions.create(token=enduser_token)
    order_actions.reserve(order_id, token=drone1_token)
    resp = _list_orders(
        api_client, admin_token, status="reserved", enduser_id=enduser_id, assigned_drone_id=drone1_id
    )
    assert order_id in _order_ids(resp)


def test_admin_order_list_has_next_flag(api_client, admin_token):
    small_page = _list_orders(api_client, admin_token, page=1, page_size=1)
    assert small_page["meta"]["has_next"] in (True, False)
    high_page = _list_orders(api_client, admin_token, page=999, page_size=50)
    assert high_page["meta"]["page"] == 999
    assert high_page["meta"]["has_next"] is False


def test_admin_order_list_status_fields(
    api_client,
    admin_token,
    order_actions,
    enduser_token,
    drone1_token,
    drone_actions,
    drone1_id,
    drone2_token,
    drone2_id,
    idle_drone1,
):
    drone_actions.ensure_idle(drone2_id)
    reserved_order = order_actions.create(token=enduser_token)
    order_actions.reserve(reserved_order, token=drone1_token)

    pickup_order = order_actions.create(token=enduser_token)
    order_actions.reserve(pickup_order, token=drone2_token)
    order_actions.pickup(pickup_order, token=drone2_token)
    canceled_order = order_actions.create(token=enduser_token)
    order_actions.cancel(canceled_order, token=enduser_token)

    reserved_list = _list_orders(api_client, admin_token, status="reserved")
    entry = next(item for item in reserved_list["data"] if item["order_id"] == reserved_order)
    assert entry["assigned_drone_id"] == drone1_id

    picked_resp = _list_orders(api_client, admin_token, status="picked_up")
    entry = next(item for item in picked_resp["data"] if item["order_id"] == pickup_order)
    assert entry["assigned_drone_id"] == drone2_id

    canceled_resp = _list_orders(api_client, admin_token, status="canceled")
    entry = next(item for item in canceled_resp["data"] if item["order_id"] == canceled_order)
    assert entry.get("canceled_at")

    order_actions.fail(reserved_order, token=drone1_token)
    order_actions.deliver(pickup_order, token=drone2_token)
