import pytest

pytestmark = pytest.mark.acceptance


def test_create_requires_auth(api_client):
    payload = {"pickup_lat": 31.9, "pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}
    response = api_client.post("/orders", json_body=payload)
    assert response.status_code == 401


def test_create_rejects_invalid_token(api_client):
    payload = {"pickup_lat": 31.9, "pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}
    response = api_client.post("/orders", token="invalid.token", json_body=payload)
    assert response.status_code == 401


def test_create_rejects_admin_token(api_client, admin_token):
    payload = {"pickup_lat": 31.9, "pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}
    api_client.post("/orders", token=admin_token, json_body=payload, expected_status=403)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param(
            {"pickup_lat": 31.9454, "pickup_lng": 35.9284, "dropoff_lat": 31.9632, "dropoff_lng": 35.9106},
            id="standard",
        ),
        pytest.param(
            {"pickup_lat": 31.945678, "pickup_lng": 35.928456, "dropoff_lat": 31.963234, "dropoff_lng": 35.910678},
            id="decimal",
        ),
        pytest.param({"pickup_lat": -90, "pickup_lng": -180, "dropoff_lat": -90, "dropoff_lng": -180}, id="boundary-min"),
        pytest.param({"pickup_lat": 90, "pickup_lng": 180, "dropoff_lat": 90, "dropoff_lng": 180}, id="boundary-max"),
        pytest.param({"pickup_lat": 0, "pickup_lng": 0, "dropoff_lat": 0, "dropoff_lng": 0}, id="zero"),
    ],
)
def test_create_accepts_valid_payloads(api_client, enduser_token, payload):
    result = api_client.post("/orders", token=enduser_token, json_body=payload, expected_status=201)
    body = result.json()
    assert body["status"] == "pending"
    assert isinstance(body["order_id"], int)
    assert body["order_id"] > 0


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({"pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="missing-pickup-lat"),
        pytest.param({"pickup_lat": 31.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="missing-pickup-lng"),
        pytest.param({"pickup_lat": 31.9, "pickup_lng": 35.9, "dropoff_lng": 36.0}, id="missing-dropoff-lat"),
        pytest.param({"pickup_lat": 31.9, "pickup_lng": 35.9, "dropoff_lat": 32.0}, id="missing-dropoff-lng"),
    ],
)
def test_create_rejects_missing_fields(api_client, enduser_token, payload):
    api_client.post("/orders", token=enduser_token, json_body=payload, expected_status=400)


def test_create_rejects_empty_body(api_client, enduser_token):
    api_client.post("/orders", token=enduser_token, raw_body="", expected_status=400)


def test_create_rejects_invalid_json(api_client, enduser_token):
    api_client.post(
        "/orders",
        token=enduser_token,
        raw_body="not-json",
        headers={"Content-Type": "application/json"},
        expected_status=400,
    )


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({"pickup_lat": 91, "pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="lat>90"),
        pytest.param({"pickup_lat": -91, "pickup_lng": 35.9, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="lat<-90"),
        pytest.param({"pickup_lat": 31.9, "pickup_lng": 181, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="lng>180"),
        pytest.param({"pickup_lat": 31.9, "pickup_lng": -181, "dropoff_lat": 32.0, "dropoff_lng": 36.0}, id="lng<-180"),
    ],
)
def test_create_rejects_out_of_range_coordinates(api_client, enduser_token, payload):
    api_client.post("/orders", token=enduser_token, json_body=payload, expected_status=400)
