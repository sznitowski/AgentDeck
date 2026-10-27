"""AgentDeck Server Companion package."""

from .models import (
    SCHEMA_VERSION,
    BINARY_VERSION,
    PROTOCOL_VERSION,
    CompanionConfig,
    CompanionProjectConfig,
    CompanionEvent,
    NotificationDestination,
    ServerResourceMetrics,
    AgentStateObservation,
    GitStateObservation,
)
from .journal import EventJournal
from .daemon import CompanionDaemon

__all__ = [
    "SCHEMA_VERSION",
    "BINARY_VERSION",
    "PROTOCOL_VERSION",
    "CompanionConfig",
    "CompanionProjectConfig",
    "CompanionEvent",
    "NotificationDestination",
    "ServerResourceMetrics",
    "AgentStateObservation",
    "GitStateObservation",
    "EventJournal",
    "CompanionDaemon",
]
