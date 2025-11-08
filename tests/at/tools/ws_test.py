#!/usr/bin/env python3
"""
WebSocket test helper for drone heartbeat testing.
Usage: python3 ws_test.py <token> <json_message>
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


async def test_heartbeat(token, message_json):
    """Send a single heartbeat message and check response."""
    uri = "ws://localhost:8080/ws/heartbeat"
    
    try:
        async with websockets.connect(
            uri, 
            additional_headers={"Authorization": f"Bearer {token}"},
            close_timeout=1, 
            open_timeout=2
        ) as ws:
            # Send message
            await ws.send(message_json)
            
            # Wait for response with timeout
            try:
                response = await asyncio.wait_for(ws.recv(), timeout=3)
                data = json.loads(response)
                
                # Print response for parsing
                print(json.dumps(data))
                
                # Exit with appropriate code
                if data.get("message") == "ok":
                    sys.exit(0)
                elif data.get("message") == "error":
                    sys.exit(1)
                elif data.get("message") == "unauthorized":
                    sys.exit(1)
                else:
                    sys.exit(1)
            except asyncio.TimeoutError:
                print(json.dumps({"error": "timeout waiting for response"}), file=sys.stderr)
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


async def test_multiple_heartbeats(token, messages):
    """Send multiple heartbeat messages on same connection."""
    uri = "ws://localhost:8080/ws/heartbeat"
    
    try:
        async with websockets.connect(
            uri,
            additional_headers={"Authorization": f"Bearer {token}"},
            close_timeout=1,
            open_timeout=2
        ) as ws:
            for msg_json in messages:
                await ws.send(msg_json)
                response = await asyncio.wait_for(ws.recv(), timeout=2)
                data = json.loads(response)
                
                if data.get("message") != "ok":
                    print(json.dumps({"error": f"message failed: {data}"}), file=sys.stderr)
                    sys.exit(1)
            
            print(json.dumps({"message": "ok", "count": len(messages)}))
            sys.exit(0)
    
    except TypeError as e:
        # Fallback for older websockets versions
        if "extra_headers" in str(e) or "additional_headers" in str(e):
            print(json.dumps({"error": "websockets version incompatibility"}), file=sys.stderr)
        else:
            print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


def main():
    if len(sys.argv) < 3:
        print("Usage: ws_test.py <token> <json_message> [json_message2 ...]", file=sys.stderr)
        sys.exit(2)
    
    token = sys.argv[1]
    messages = sys.argv[2:]
    
    if len(messages) == 1:
        asyncio.run(test_heartbeat(token, messages[0]))
    else:
        asyncio.run(test_multiple_heartbeats(token, messages))


if __name__ == "__main__":
    main()
