"""Backward-compatibility stub for tea_inventory_api.py.

Legacy entry point kept for backward compatibility with existing documentation
and deployment scripts. The canonical entry point is now `tea_inventory_api.py`.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Ensure infra/modal directory is in sys.path for direct script execution
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

try:
    from tea_inventory_api import (  # type: ignore[import-not-found]
        REQUIREMENTS,
        api,
        app,
        debug_origins,
        image,
        migrate_database,
    )
except ImportError:
    from infra.modal.tea_inventory_api import (
        REQUIREMENTS,
        api,
        app,
        debug_origins,
        image,
        migrate_database,
    )

__all__ = [
    "REQUIREMENTS",
    "image",
    "app",
    "migrate_database",
    "debug_origins",
    "api",
]
