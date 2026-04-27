"""
SSRF guard for outbound fetches. Blocks loopback, private ranges, link-local,
metadata endpoints, and the .local/.internal/.localhost suffixes.

Adapted from the DataPoints backend.
"""

import ipaddress
import socket
from urllib.parse import urlparse


class SSRFError(Exception):
    """Raised when a URL fails SSRF validation."""


_BLOCKED_NETWORKS = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("0.0.0.0/8"),
    ipaddress.ip_network("255.255.255.255/32"),
    ipaddress.ip_network("192.0.2.0/24"),
    ipaddress.ip_network("198.51.100.0/24"),
    ipaddress.ip_network("203.0.113.0/24"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
    ipaddress.ip_network("fe80::/10"),
]

_BLOCKED_HOSTNAMES = {
    "localhost",
    "localhost.localdomain",
    "ip6-localhost",
    "ip6-loopback",
    "metadata",
    "metadata.google.internal",
    "kubernetes.default",
    "kubernetes.default.svc",
}

_ALLOWED_SCHEMES = {"http", "https"}


def _ip_blocked(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    return any(ip in net for net in _BLOCKED_NETWORKS)


def validate_url(url: str, *, resolve_dns: bool = True) -> str:
    """Raise SSRFError if `url` targets internal/blocked hosts. Returns `url`."""
    try:
        parsed = urlparse(url)
    except Exception as e:
        raise SSRFError(f"Invalid URL format: {e}")

    if parsed.scheme.lower() not in _ALLOWED_SCHEMES:
        raise SSRFError(
            f"URL scheme '{parsed.scheme}' is not allowed. Use http or https."
        )
    if not parsed.hostname:
        raise SSRFError("URL must include a hostname")

    hostname = parsed.hostname.lower()
    if hostname in _BLOCKED_HOSTNAMES:
        raise SSRFError(f"Access to '{hostname}' is not allowed")

    try:
        ip = ipaddress.ip_address(hostname)
        if _ip_blocked(str(ip)):
            raise SSRFError(f"Access to IP address '{ip}' is not allowed")
    except ValueError:
        if hostname.endswith((".local", ".internal", ".localhost")):
            raise SSRFError(f"Access to '{hostname}' is not allowed")

    if resolve_dns:
        try:
            addrinfo = socket.getaddrinfo(
                hostname, parsed.port or 80, proto=socket.IPPROTO_TCP
            )
            for _, _, _, _, sockaddr in addrinfo:
                if _ip_blocked(sockaddr[0]):
                    raise SSRFError(
                        f"Hostname '{hostname}' resolves to blocked IP "
                        f"address '{sockaddr[0]}'"
                    )
        except socket.gaierror:
            pass
        except SSRFError:
            raise
        except Exception:
            pass

    return url
