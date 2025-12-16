import pytest

pytestmark = pytest.mark.acceptance


def test_health_endpoint_ok(api_client):
    result = api_client.get("/health", expected_status=200)
    content_type = result.response.headers.get("Content-Type", "")
    assert content_type.startswith("text/plain")
    assert "ok" in result.text.lower()
