#!/usr/bin/env python3
"""
WebSocket helper that sends an assignment acknowledgement over the heartbeat channel.
Usage: python3 ws_send_ack.py <token> <order_id> <status>

The server expects status values of either \"accepted\" or \"declined\" and responds
with {\"message\":\"acknowledged\"} when the payload is valid.
"""

import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print("ERROR: websockets module not installed (pip3 install websockets)", file=sys.stderr)
    sys.exit(2)


STATUS_MAP = {
    "accept": "accepted",
    "accepted": "accepted",
    "decline": "declined",
    "declined": "declined",
    "reject": "declined",
}


async def send_acknowledgment(token: str, order_id: int, status: str) -> None:
    uri = "ws://localhost:8080/ws/heartbeat"
    payload = {
        "type": "assignment_ack",
        "order_id": order_id,
        "status": STATUS_MAP[status],
    }

    async with websockets.connect(
        uri,
        additional_headers={"Authorization": f"Bearer {token}"},
        close_timeout=1,
        open_timeout=2,
    ) as ws:
        await ws.send(json.dumps(payload))

        try:
            response = await asyncio.wait_for(ws.recv(), timeout=3)
        except asyncio.TimeoutError:
            print(json.dumps({"error": "timeout waiting for ack response"}), file=sys.stderr)
            sys.exit(1)

        data = json.loads(response)
        print(json.dumps(data))

        if data.get("message") == "acknowledged":
            sys.exit(0)
        else:
            sys.exit(1)


def main() -> None:
    if len(sys.argv) != 4:
        print("Usage: python3 ws_send_ack.py <token> <order_id> <status>", file=sys.stderr)
        sys.exit(2)

    token = sys.argv[1]
    try:
        order_id = int(sys.argv[2])
    except ValueError:
        print("ERROR: order_id must be an integer", file=sys.stderr)
        sys.exit(2)

    status_raw = sys.argv[3].lower()
    if status_raw not in STATUS_MAP:
        print("ERROR: status must be one of: accept, accepted, decline, declined, reject", file=sys.stderr)
        sys.exit(2)

    try:
        asyncio.run(send_acknowledgment(token, order_id, status_raw))
    except websockets.exceptions.InvalidStatusCode as exc:
        print(json.dumps({"error": f"invalid status code: {exc.status_code}"}), file=sys.stderr)
        sys.exit(1)
    except ConnectionRefusedError:
        print(json.dumps({"error": "connection refused - is server running?"}), file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
