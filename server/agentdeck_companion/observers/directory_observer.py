"""Working directory observer for AgentDeck Server Companion."""

import os
from pathlib import Path


class DirectoryObserver:
    """Verifies that project working directories exist and are accessible."""

    def observe(self, path: str) -> bool:
        if not path or not isinstance(path, str):
            return False
        try:
            p = Path(path)
            return p.exists() and p.is_dir() and os.access(str(p), os.R_OK)
        except Exception:
            return False
