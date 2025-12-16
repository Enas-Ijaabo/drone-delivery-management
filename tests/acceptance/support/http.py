from dataclasses import dataclass
from typing import Any, Dict, Optional

import requests


@dataclass
class ApiResult:
    """Wrapper that exposes parsed JSON while keeping original response handy."""

    response: requests.Response

    @property
    def status_code(self) -> int:
        return self.response.status_code

    @property
    def text(self) -> str:
        return self.response.text

    def json(self) -> Any:
        if not self.response.content:
            return None
        return self.response.json()


class ApiClient:
    """Thin HTTP client with auth + assertion helpers for acceptance tests."""

    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")
        self._session = requests.Session()

    def close(self) -> None:
        self._session.close()

    def request(
        self,
        method: str,
        path: str,
        *,
        token: Optional[str] = None,
        json_body: Optional[Dict[str, Any]] = None,
        raw_body: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        expected_status: Optional[int] = None,
    ) -> ApiResult:
        url = f"{self.base_url}{path}"
        request_headers: Dict[str, str] = {"Content-Type": "application/json"}
        if headers:
            request_headers.update(headers)
        if token:
            request_headers["Authorization"] = f"Bearer {token}"

        if raw_body is not None and json_body is not None:
            raise ValueError("Provide either json_body or raw_body, not both.")

        data = None
        json_payload = None
        if raw_body is not None:
            data = raw_body
        elif json_body is not None:
            json_payload = json_body

        response = self._session.request(
            method=method,
            url=url,
            headers=request_headers,
            json=json_payload,
            data=data,
        )

        if expected_status is not None:
            assert (
                response.status_code == expected_status
            ), f"{method} {path} expected {expected_status}, got {response.status_code}: {response.text}"

        return ApiResult(response=response)

    def get(
        self,
        path: str,
        *,
        token: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        expected_status: Optional[int] = None,
    ) -> ApiResult:
        return self.request("GET", path, token=token, headers=headers, expected_status=expected_status)

    def post(
        self,
        path: str,
        *,
        token: Optional[str] = None,
        json_body: Optional[Dict[str, Any]] = None,
        raw_body: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        expected_status: Optional[int] = None,
    ) -> ApiResult:
        return self.request(
            "POST",
            path,
            token=token,
            json_body=json_body,
            raw_body=raw_body,
            headers=headers,
            expected_status=expected_status,
        )

    def patch(
        self,
        path: str,
        *,
        token: Optional[str] = None,
        json_body: Optional[Dict[str, Any]] = None,
        raw_body: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
        expected_status: Optional[int] = None,
    ) -> ApiResult:
        return self.request(
            "PATCH",
            path,
            token=token,
            json_body=json_body,
            raw_body=raw_body,
            headers=headers,
            expected_status=expected_status,
        )
