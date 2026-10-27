"""Server resource metrics observer using Linux kernel interfaces (/proc)."""

import os
import time
from typing import Optional, Tuple
from ..models import ServerResourceMetrics, utc_now


class ServerMetricsObserver:
    """Collects CPU, memory, and disk utilization metrics from Linux /proc."""

    def __init__(self):
        self._last_cpu_times: Optional[Tuple[int, int]] = None  # (idle, total)

    def read_memory_percent(self) -> Optional[float]:
        """Reads /proc/meminfo to compute memory utilization percentage."""
        meminfo_path = "/proc/meminfo"
        if not os.path.exists(meminfo_path):
            return None

        total_kb = None
        available_kb = None
        free_kb = None
        buffers_kb = None
        cached_kb = None

        try:
            with open(meminfo_path, "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split(":")
                    if len(parts) < 2:
                        continue
                    key = parts[0].strip()
                    val_str = parts[1].strip().split()[0]
                    if not val_str.isdigit():
                        continue
                    val = int(val_str)
                    if key == "MemTotal":
                        total_kb = val
                    elif key == "MemAvailable":
                        available_kb = val
                    elif key == "MemFree":
                        free_kb = val
                    elif key == "Buffers":
                        buffers_kb = val
                    elif key == "Cached":
                        cached_kb = val

            if total_kb and total_kb > 0:
                if available_kb is not None:
                    used = total_kb - available_kb
                elif free_kb is not None and buffers_kb is not None and cached_kb is not None:
                    used = total_kb - (free_kb + buffers_kb + cached_kb)
                elif free_kb is not None:
                    used = total_kb - free_kb
                else:
                    return None
                return round((used / total_kb) * 100.0, 1)
        except Exception:
            return None
        return None

    def read_disk_percent(self, path: str = "/") -> Optional[float]:
        """Computes disk space utilization percentage via statvfs."""
        try:
            st = os.statvfs(path)
            total = st.f_blocks * st.f_frsize
            free = st.f_bavail * st.f_frsize
            if total > 0:
                used = total - free
                return round((used / total) * 100.0, 1)
        except Exception:
            return None
        return None

    def read_cpu_percent(self) -> Optional[float]:
        """Computes CPU utilization percentage delta from /proc/stat."""
        stat_path = "/proc/stat"
        if not os.path.exists(stat_path):
            return None

        try:
            with open(stat_path, "r", encoding="utf-8") as f:
                first_line = f.readline()
                if not first_line.startswith("cpu "):
                    return None
                parts = [int(p) for p in first_line.split()[1:] if p.isdigit()]
                if len(parts) < 4:
                    return None

                idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
                total = sum(parts)

                if self._last_cpu_times is not None:
                    prev_idle, prev_total = self._last_cpu_times
                    delta_idle = idle - prev_idle
                    delta_total = total - prev_total
                    self._last_cpu_times = (idle, total)

                    if delta_total > 0:
                        used = delta_total - delta_idle
                        return round(max(0.0, min(100.0, (used / delta_total) * 100.0)), 1)
                else:
                    self._last_cpu_times = (idle, total)
                    return 0.0
        except Exception:
            return None
        return None

    def observe(self, disk_path: str = "/") -> ServerResourceMetrics:
        """Observes full resource metrics."""
        return ServerResourceMetrics(
            cpu_percent=self.read_cpu_percent(),
            memory_percent=self.read_memory_percent(),
            disk_percent=self.read_disk_percent(disk_path),
            observed_at=utc_now(),
        )
