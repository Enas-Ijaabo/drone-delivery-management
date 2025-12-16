import pytest

pytestmark = pytest.mark.acceptance


@pytest.mark.parametrize(
    "username,expected_role",
    [
        pytest.param("admin", "admin", id="admin"),
        pytest.param("enduser1", "enduser", id="enduser"),
        pytest.param("drone1", "drone", id="drone"),
    ],
)
def test_token_issuance(api_client, username, expected_role):
    result = api_client.post(
        "/auth/token",
        json_body={"name": username, "password": "password"},
        expected_status=200,
    )
    body = result.json()
    assert body["token_type"] == "bearer"
    assert body["user"]["type"] == expected_role
    assert body["user"]["name"] == username
    assert isinstance(body["access_token"], str) and body["access_token"]


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({"name": "admin", "password": "wrong"}, id="wrong-password"),
        pytest.param({"name": "nouser", "password": "password"}, id="unknown-user"),
    ],
)
def test_token_invalid_credentials(api_client, payload):
    api_client.post("/auth/token", json_body=payload, expected_status=401)


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param({}, id="empty-body"),
        pytest.param({"password": "password"}, id="missing-name"),
        pytest.param({"name": "admin"}, id="missing-password"),
        pytest.param({"name": "", "password": "password"}, id="empty-name"),
        pytest.param({"name": "admin", "password": ""}, id="empty-password"),
    ],
)
def test_token_validation_errors(api_client, payload):
    api_client.post("/auth/token", json_body=payload, expected_status=400)


def test_token_invalid_json(api_client):
    api_client.post("/auth/token", raw_body="not-json", expected_status=400)
