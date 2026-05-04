"""Test bootstrap: makes `app.*` imports work when running pytest from
the `ironlog-server/` directory."""

import os
import sys

os.environ.setdefault("JWT_SECRET", "test-jwt-secret")

# Add server root to import path so `from app.schemas.*` works.
_HERE = os.path.dirname(os.path.abspath(__file__))
_SERVER_ROOT = os.path.dirname(_HERE)
if _SERVER_ROOT not in sys.path:
    sys.path.insert(0, _SERVER_ROOT)
