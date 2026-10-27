"""Outbound event forwarding queue (Outbox) for AgentDeck Server Companion."""

from dataclasses import dataclass
from datetime import datetime
import json
import logging
import time
from typing import List, Dict, Any, Optional
import urllib.request
import urllib.error

from .models import CompanionEvent, CompanionRelayConfig, utc_now

logger = logging.getLogger("agentdeck.companion.outbox")


@dataclass
class OutboxEntry:
    event: CompanionEvent
    attempts: int = 0
    next_retry_at: float = 0.0
    last_error: Optional[str] = None


class CompanionOutbox:
    """Manages asynchronous, retryable outbound dispatch of companion events to the Push Relay."""

    def __init__(self, config: CompanionRelayConfig):
        self.config = config
        self._queue: List[OutboxEntry] = []

    @property
    def is_enabled(self) -> bool:
        return self.config.enabled and bool(self.config.url)

    @property
    def pending_count(self) -> int:
        return len(self._queue)

    def enqueue(self, event: CompanionEvent) -> None:
        """Enqueues an event for outbound relay forwarding."""
        if not self.is_enabled:
            return
        self._queue.append(OutboxEntry(event=event))

    def flush(self) -> int:
        """Attempts to flush pending events to the Push Relay. Returns number of successful deliveries."""
        if not self.is_enabled or not self._queue:
            return 0

        now = time.time()
        delivered_count = 0
        remaining: List[OutboxEntry] = []

        for entry in self._queue:
            if entry.next_retry_at > now:
                remaining.append(entry)
                continue

            success = self._send_event(entry.event)
            if success:
                delivered_count += 1
            else:
                entry.attempts += 1
                if entry.attempts < self.config.max_retries:
                    # Exponential backoff: 2s, 4s, 8s... capped at 60s
                    backoff = min(60.0, 2.0 ** entry.attempts)
                    entry.next_retry_at = now + backoff
                    remaining.append(entry)
                else:
                    logger.warning(
                        f"Dropping event {entry.event.event_id} from outbox after {entry.attempts} failed attempts"
                    )

        self._queue = remaining
        return delivered_count

    def _send_event(self, event: CompanionEvent) -> bool:
        """Sends an HTTP POST to the Push Relay endpoint."""
        try:
            payload = json.dumps(event.to_dict(), ensure_ascii=False).encode("utf-8")
            headers = {
                "Content-Type": "application/json; charset=utf-8",
                "X-Companion-Id": self.config.companion_id,
                "X-Companion-Secret": self.config.companion_secret,
                "User-Agent": "agentdeck-companion/0.1.0",
            }
            req = urllib.request.Request(
                self.config.url,
                data=payload,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=self.config.timeout_sec) as resp:
                if 200 <= resp.status < 300:
                    return True
                return False
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
            logger.debug(f"Outbox forward failed: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected outbox error: {e}")
            return False
