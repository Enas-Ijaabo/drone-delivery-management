#!/usr/bin/env python3
"""
WebSocket test helper for receiving assignment notifications.
Usage: python3 ws_assignment_test.py <token> <timeout_seconds>
"""

import sys
import json
import asyncio

try:
    import websockets
except ImportError:
    print("ERROR: websockets module not installed", file=sys.stderr)
    print("Install with: pip3 install websockets", file=sys.stderr)
    sys.exit(2)


async def wait_for_assignment(token, timeout):
    """Connect to WebSocket and wait for assignment notification."""
    uri = "ws://localhost:8080/ws/heartbeat"
    
    try:
        async with websockets.connect(
            uri, 
            additional_headers={"Authorization": f"Bearer {token}"},
            close_timeout=1, 
            open_timeout=2
        ) as ws:
            # Wait for assignment notification
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=timeout)
                data = json.loads(response)
                
                # Check if it's an assignment message
                if data.get("type") == "assignment":
                    print(json.dumps(data))
                    sys.exit(0)
                else:
                    print(json.dumps({"error": f"unexpected message type: {data.get('type')}"}), file=sys.stderr)
                    sys.exit(1)
                    
            except asyncio.TimeoutError:
                print(json.dumps({"error": f"timeout after {timeout}s waiting for assignment"}), file=sys.stderr)
                sys.exit(1)
                
    except asyncio.TimeoutError:
        print(json.dumps({"error": "connection timeout"}), file=sys.stderr)
        sys.exit(1)
    except websockets.exceptions.InvalidStatusCode as e:
        print(json.dumps({"error": f"invalid status: {e.status_code}"}), file=sys.stderr)
        sys.exit(1)
    except ConnectionRefusedError:
        print(json.dumps({"error": "connection refused - is server running?"}), file=sys.stderr)
        sys.exit(1)
    except TypeError as e:
        if "extra_headers" in str(e) or "additional_headers" in str(e):
            print(json.dumps({"error": "websockets version incompatibility"}), file=sys.stderr)
        else:
            print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 ws_assignment_test.py <token> <timeout_seconds>", file=sys.stderr)
        sys.exit(2)
    
    token = sys.argv[1]
    try:
        timeout = float(sys.argv[2])
    except ValueError:
        print("ERROR: timeout must be a number", file=sys.stderr)
        sys.exit(2)
    
    asyncio.run(wait_for_assignment(token, timeout))
