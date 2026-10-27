"""Append-safe, bounded, monotonic Event Journal for AgentDeck Server Companion."""

from datetime import timedelta
import json
import os
from pathlib import Path
from typing import List, Tuple, Optional, Callable, Dict, Any

from .models import CompanionEvent, utc_now, format_iso, parse_iso


class EventJournal:
    """Manages an append-safe JSON Lines journal of CompanionEvent records."""

    def __init__(self, journal_path: str, max_events: int = 1000, max_age_days: int = 7):
        self.journal_path = Path(journal_path)
        self.max_events = max_events
        self.max_age_days = max_age_days
        self._current_sequence = 0
        self._ensure_journal_dir()
        self._recover_last_sequence()

    def _ensure_journal_dir(self) -> None:
        if not self.journal_path.parent.exists():
            self.journal_path.parent.mkdir(parents=True, exist_ok=True)

    def _recover_last_sequence(self) -> None:
        """Reads the journal file to recover the highest sequence number."""
        if not self.journal_path.exists():
            self._current_sequence = 0
            return

        max_seq = 0
        try:
            with open(self.journal_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                        seq = int(record.get("sequence", 0))
                        if seq > max_seq:
                            max_seq = seq
                    except Exception:
                        continue
        except Exception:
            max_seq = 0
        self._current_sequence = max_seq

    @property
    def current_sequence(self) -> int:
        return self._current_sequence

    def append(self, event_builder: Callable[[int], CompanionEvent]) -> CompanionEvent:
        """Assigns the next monotonic sequence number and appends the event to the journal."""
        self._current_sequence += 1
        event = event_builder(self._current_sequence)
        line = json.dumps(event.to_dict(), ensure_ascii=False)

        self._ensure_journal_dir()
        with open(self.journal_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()

        return event

    def query(self, after_sequence: int = 0, limit: int = 100) -> Tuple[List[CompanionEvent], int, bool]:
        """Queries events where sequence > after_sequence, bounded by limit.
        
        Returns: (events, last_sequence, has_more)
        """
        if not self.journal_path.exists():
            return ([], after_sequence, False)

        events: List[CompanionEvent] = []
        matched_total = 0
        limit = max(1, min(limit, 500))

        with open(self.journal_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    seq = int(data.get("sequence", 0))
                    if seq > after_sequence:
                        matched_total += 1
                        if len(events) < limit:
                            events.append(CompanionEvent.from_dict(data))
                except Exception:
                    continue

        last_seq = events[-1].sequence if events else after_sequence
        has_more = matched_total > len(events)
        return (events, last_seq, has_more)

    def prune(self) -> int:
        """Prunes the journal to satisfy max_events and max_age_days limits.
        
        Returns the number of events removed.
        """
        if not self.journal_path.exists():
            return 0

        cutoff = utc_now() - timedelta(days=self.max_age_days)
        valid_records: List[Dict[str, Any]] = []

        with open(self.journal_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                    dt_str = data.get("detectedAt")
                    if dt_str:
                        dt = parse_iso(dt_str)
                        if dt < cutoff:
                            continue
                    valid_records.append(data)
                except Exception:
                    continue

        # Cap to max_events (FIFO: keep newest)
        if len(valid_records) > self.max_events:
            valid_records = valid_records[-self.max_events:]

        # Atomic rewrite
        temp_path = self.journal_path.with_suffix(".tmp")
        with open(temp_path, "w", encoding="utf-8") as f:
            for record in valid_records:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())

        os.replace(temp_path, self.journal_path)
        self._recover_last_sequence()
        return len(valid_records)

    def stats(self) -> Dict[str, Any]:
        """Returns statistics on the current journal."""
        if not self.journal_path.exists():
            return {
                "totalEvents": 0,
                "firstSequence": 0,
                "lastSequence": self._current_sequence,
                "fileSizeBytes": 0,
            }

        first_seq = 0
        last_seq = 0
        count = 0
        with open(self.journal_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                count += 1
                try:
                    data = json.loads(line)
                    seq = int(data.get("sequence", 0))
                    if first_seq == 0:
                        first_seq = seq
                    last_seq = seq
                except Exception:
                    continue

        return {
            "totalEvents": count,
            "firstSequence": first_seq,
            "lastSequence": last_seq or self._current_sequence,
            "fileSizeBytes": self.journal_path.stat().st_size if self.journal_path.exists() else 0,
        }
