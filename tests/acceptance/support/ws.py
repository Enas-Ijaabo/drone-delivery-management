import json
import time
from contextlib import contextmanager
from typing import Dict, List
from urllib.parse import urlparse, urlunparse

import websocket


def _ws_url(base_url: str, path: str) -> str:
    parsed = urlparse(base_url)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    netloc = parsed.netloc or parsed.path  # handle bare host without scheme
    return urlunparse((scheme, netloc, path, "", "", ""))


@contextmanager
def websocket_connection(base_url: str, token: str, path: str = "/ws/heartbeat", timeout: int = 5):
    url = _ws_url(base_url, path)
    headers = [f"Authorization: Bearer {token}"]
    ws = websocket.create_connection(url, header=headers, timeout=timeout)
    try:
        yield ws
    finally:
        ws.close()


def send_heartbeat(base_url: str, token: str, lat: float, lng: float, *, timeout: int = 5) -> Dict:
    payload = json.dumps({"type": "heartbeat", "lat": lat, "lng": lng})
    with websocket_connection(base_url, token, timeout=timeout) as ws:
        ws.send(payload)
        response = ws.recv()
        return json.loads(response)


def send_multiple_heartbeats(base_url: str, token: str, coords: List[Dict[str, float]]) -> List[Dict]:
    responses: List[Dict] = []
    with websocket_connection(base_url, token) as ws:
        for coord in coords:
            payload = {"type": "heartbeat", **coord}
            ws.send(json.dumps(payload))
            responses.append(json.loads(ws.recv()))
    return responses


def wait_for_assignment(base_url: str, token: str, timeout: int = 10) -> Dict:
    deadline = time.time() + timeout
    with websocket_connection(base_url, token) as ws:
        while time.time() < deadline:
            remaining = deadline - time.time()
            ws.settimeout(max(0.1, remaining))
            message = ws.recv()
            data = json.loads(message)
            if data.get("type") == "assignment":
                return data
        raise TimeoutError(f"No assignment message within {timeout}s")


def send_assignment_ack(base_url: str, token: str, order_id: int, status: str) -> Dict:
    payload = {"type": "assignment_ack", "order_id": order_id, "status": status}
    with websocket_connection(base_url, token) as ws:
        ws.send(json.dumps(payload))
        return json.loads(ws.recv())
