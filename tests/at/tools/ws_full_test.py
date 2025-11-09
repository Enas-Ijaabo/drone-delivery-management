#!/usr/bin/env python3
"""
Unified WebSocket helper for assignment tests.

Usage:
  python3 ws_full_test.py <token> wait_assignment <timeout>
  python3 ws_full_test.py <token> send_ack <order_id> <status>
  python3 ws_full_test.py <token> heartbeat <lat> <lng>
"""

import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print("ERROR: websockets module not installed (pip3 install websockets)", file=sys.stderr)
    sys.exit(2)

WS_URL = "ws://localhost:8080/ws/heartbeat"
STATUS_MAP = {
    "accept": "accepted",
    "accepted": "accepted",
    "decline": "declined",
    "declined": "declined",
    "reject": "declined",
}


async def wait_for_assignment(token: str, timeout: float) -> int:
    async with websockets.connect(
        WS_URL,
        additional_headers={"Authorization": f"Bearer {token}"},
        close_timeout=1,
        open_timeout=2,
    ) as ws:
        try:
            while True:
                message = await asyncio.wait_for(ws.recv(), timeout=timeout)
                data = json.loads(message)
                if data.get("type") == "assignment":
                    print(json.dumps(data))
                    return 0
        except asyncio.TimeoutError:
            print(json.dumps({"error": f"timeout after {timeout}s"}), file=sys.stderr)
            return 1


async def send_assignment_ack(token: str, order_id: int, status: str) -> int:
    payload = {
        "type": "assignment_ack",
        "order_id": order_id,
        "status": STATUS_MAP[status],
    }
    async with websockets.connect(
        WS_URL,
        additional_headers={"Authorization": f"Bearer {token}"},
        close_timeout=1,
        open_timeout=2,
    ) as ws:
        await ws.send(json.dumps(payload))
        try:
            response = await asyncio.wait_for(ws.recv(), timeout=3)
        except asyncio.TimeoutError:
            print(json.dumps({"error": "timeout waiting for ack response"}), file=sys.stderr)
            return 1

        data = json.loads(response)
        print(json.dumps(data))
        return 0 if data.get("message") == "acknowledged" else 1


async def send_heartbeat(token: str, lat: float, lng: float) -> int:
    payload = {"type": "heartbeat", "lat": lat, "lng": lng}
    async with websockets.connect(
        WS_URL,
        additional_headers={"Authorization": f"Bearer {token}"},
        close_timeout=1,
        open_timeout=2,
    ) as ws:
        await ws.send(json.dumps(payload))
        try:
            response = await asyncio.wait_for(ws.recv(), timeout=3)
        except asyncio.TimeoutError:
            print(json.dumps({"error": "timeout waiting for heartbeat ack"}), file=sys.stderr)
            return 1

        data = json.loads(response)
        print(json.dumps(data))
        return 0 if data.get("message") == "ok" else 1


def main() -> None:
    if len(sys.argv) < 4:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)

    token = sys.argv[1]
    command = sys.argv[2]
    args = sys.argv[3:]

    try:
        if command == "wait_assignment":
            if len(args) != 1:
                raise ValueError("wait_assignment requires timeout argument")
            timeout = float(args[0])
            rc = asyncio.run(wait_for_assignment(token, timeout))
        elif command == "send_ack":
            if len(args) != 2:
                raise ValueError("send_ack requires order_id and status")
            order_id = int(args[0])
            status_key = args[1].lower()
            if status_key not in STATUS_MAP:
                raise ValueError("status must be one of: accept, accepted, decline, declined, reject")
            rc = asyncio.run(send_assignment_ack(token, order_id, status_key))
        elif command == "heartbeat":
            if len(args) != 2:
                raise ValueError("heartbeat requires lat and lng")
            lat = float(args[0])
            lng = float(args[1])
            rc = asyncio.run(send_heartbeat(token, lat, lng))
        else:
            raise ValueError(f"unknown command: {command}")
    except Exception as exc:  # pylint: disable=broad-except
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)

    sys.exit(rc)


if __name__ == "__main__":
    main()
