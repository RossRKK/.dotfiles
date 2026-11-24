"""An ACP agent that only opens a session: it answers agentic's handshake so a
chat gets a session id, then stays quiet. Tests send the agent's updates
themselves, through agentic's client."""

import json
import sys

RESULTS = {
    "initialize": {
        "protocolVersion": 1,
        "agentCapabilities": {"loadSession": False, "promptCapabilities": {}},
        "authMethods": [],
    },
    "session/new": {"sessionId": "fake-session"},
    "session/list": {"sessions": []},
}


def main() -> None:
    for line in sys.stdin:
        message = json.loads(line)
        if "id" in message and "method" in message:
            reply = {"jsonrpc": "2.0", "id": message["id"], "result": RESULTS.get(message["method"], {})}
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
