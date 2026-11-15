"""Start the Cycl0ps server on port 8000 for BOTH IPv4 and IPv6.

Why: phones often reach the laptop by its name (for example MyMac.local). That name
gives IPv6 addresses as well as the normal IPv4 one, and a server that only listens on
IPv4 makes some phone requests fail at random. This script listens on both.

    python run.py            (port 8000)
    python run.py 8080       (another port)
"""

import asyncio
import socket
import sys

import uvicorn


def listen(family: socket.AddressFamily, host: str, port: int) -> socket.socket:
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)  # IPv4 has its own socket
    sock.bind((host, port))
    return sock


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    sockets = [listen(socket.AF_INET, "0.0.0.0", port)]
    try:
        sockets.append(listen(socket.AF_INET6, "::", port))
    except OSError as error:  # no IPv6 on this machine: IPv4 alone still works
        print(f"IPv6 not available ({error}); listening on IPv4 only.")
    print(f"Cycl0ps server on port {port}. Dashboard: http://localhost:{port}/app/#/dashboard")
    server = uvicorn.Server(uvicorn.Config("main:app", log_level="info"))
    asyncio.run(server.serve(sockets=sockets))


if __name__ == "__main__":
    main()
