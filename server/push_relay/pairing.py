"""Pairing codes, installation tokens and brute-force limiting for the Push Relay.

Security notes:
- Pairing codes (80 bits) and installation tokens (256 bits) come from ``secrets``.
- Only SHA-256 digests are ever stored by the relay. High-entropy random values do not
  need a slow KDF; a leaked database cannot be reversed into usable credentials.
- Plaintext values are returned exactly once to the caller and must never be logged.
"""

import base64
import hashlib
import re
import secrets
import threading
import time
from typing import Callable, List, Optional

PAIRING_CODE_BYTES = 10  # 80 bits -> 16 base32 characters
DEFAULT_PAIRING_TTL_SECONDS = 10 * 60
MAX_PAIRING_TTL_SECONDS = 15 * 60
TOKEN_PREFIX = "adt_"

_CODE_RE = re.compile(r"^[A-Z2-7]{16}$")
INSTALLATION_ID_RE = re.compile(r"^[A-Za-z0-9_.\-]{8,64}$")


def generate_pairing_code() -> str:
    """Returns a random code formatted as ABCD-EFGH-IJKL-MNOP."""
    raw = base64.b32encode(secrets.token_bytes(PAIRING_CODE_BYTES)).decode("ascii")
    return "-".join(raw[i : i + 4] for i in range(0, 16, 4))


def normalize_pairing_code(code: object) -> Optional[str]:
    """Normalizes user input; returns None when the shape is not a valid code."""
    if not isinstance(code, str):
        return None
    cleaned = code.strip().upper().replace("-", "").replace(" ", "")
    return cleaned if _CODE_RE.match(cleaned) else None


def generate_installation_token() -> str:
    return TOKEN_PREFIX + secrets.token_urlsafe(32)


def hash_secret(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class FailureLimiter:
    """Global sliding-window limiter for failed pairing attempts.

    The relay listens on loopback behind Caddy, so every request shares one peer
    address. A global window is therefore the only sound choice.
    """

    def __init__(
        self,
        max_failures: int = 10,
        window_seconds: float = 60.0,
        clock: Callable[[], float] = time.monotonic,
    ):
        self.max_failures = max_failures
        self.window_seconds = window_seconds
        self._clock = clock
        self._failures: List[float] = []
        self._lock = threading.Lock()

    def _prune(self, now: float) -> None:
        cutoff = now - self.window_seconds
        self._failures = [t for t in self._failures if t > cutoff]

    def is_blocked(self) -> bool:
        with self._lock:
            self._prune(self._clock())
            return len(self._failures) >= self.max_failures

    def record_failure(self) -> None:
        with self._lock:
            now = self._clock()
            self._prune(now)
            self._failures.append(now)
