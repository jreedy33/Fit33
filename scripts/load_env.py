"""
Auto-loads .env file from the repo root into os.environ.
Import this at the top of any script that needs Supabase credentials:

    import load_env  # noqa: F401

No external dependencies required.
"""
import os
from pathlib import Path

_env_file = Path(__file__).resolve().parent.parent / '.env'

if _env_file.exists():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            os.environ.setdefault(key.strip(), value.strip())
