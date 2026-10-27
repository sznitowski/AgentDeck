"""Git repository observer for AgentDeck Server Companion (read-only)."""

from pathlib import Path
import subprocess
from typing import Optional
from ..models import GitStateObservation, utc_now


class GitObserver:
    """Inspects Git repository status in a strictly read-only manner."""

    def __init__(self, timeout_sec: int = 5):
        self.timeout_sec = timeout_sec

    def observe(self, working_directory: str) -> GitStateObservation:
        work_dir = Path(working_directory)
        if not work_dir.exists():
            return GitStateObservation(
                is_repository=False,
                is_clean=True,
                error="Working directory does not exist",
                observed_at=utc_now(),
            )

        try:
            # 1. Run git status --porcelain=v2 --branch
            res = subprocess.run(
                ["git", "-C", str(work_dir), "status", "--porcelain=v2", "--branch"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.timeout_sec,
            )

            if res.returncode != 0:
                err_text = res.stderr.strip()
                is_not_repo = "not a git repository" in err_text.lower()
                return GitStateObservation(
                    is_repository=not is_not_repo,
                    is_clean=True,
                    error=err_text if not is_not_repo else None,
                    observed_at=utc_now(),
                )

            # 2. Parse porcelain output
            branch = None
            conflicts = 0
            changed_count = 0

            for line in res.stdout.strip().split("\n"):
                line = line.strip()
                if not line:
                    continue

                if line.startswith("# branch.head "):
                    branch = line.split(" ", 2)[2]
                    if branch == "(detached)":
                        branch = "DETACHED"
                elif line.startswith("u ") or line.startswith("1 u"):
                    conflicts += 1
                    changed_count += 1
                elif line.startswith("1 ") or line.startswith("2 ") or line.startswith("? "):
                    changed_count += 1

            return GitStateObservation(
                conflict_count=conflicts,
                is_clean=(changed_count == 0),
                branch=branch,
                is_repository=True,
                observed_at=utc_now(),
            )

        except subprocess.TimeoutExpired:
            return GitStateObservation(
                is_repository=True,
                is_clean=True,
                error="Git status query timed out",
                observed_at=utc_now(),
            )
        except Exception as e:
            return GitStateObservation(
                is_repository=False,
                is_clean=True,
                error=str(e),
                observed_at=utc_now(),
            )
