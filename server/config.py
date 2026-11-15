"""Settings read from server/.env (or the environment). See .env.example."""

import os

from dotenv import load_dotenv

load_dotenv()


def _bool(name: str, default: bool) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


DEMO_MODE = _bool("DEMO_MODE", True)

# Add the 14 made-up demo workers on seed / demo reset. false = only real people.
DEMO_WORKERS = _bool("DEMO_WORKERS", True)

SITE_NAME = os.environ.get("SITE_NAME", "Arlington Site")
SITE_CODE = os.environ.get("SITE_CODE", "ARL-0412")
SUPERVISOR_PHONE = os.environ.get("SUPERVISOR_PHONE", "+10000000000")

CHERT_API_KEY = os.environ.get("CHERT_API_KEY", "")
CHERT_BASE_URL = os.environ.get("CHERT_BASE_URL", "")

# Rescue starts when this many different phones feel a shock inside the window.
COLLAPSE_PHONES = int(os.environ.get("COLLAPSE_PHONES", "3"))
COLLAPSE_WINDOW_SEC = float(os.environ.get("COLLAPSE_WINDOW_SEC", "5"))

# A phone with no ping for this long is shown as "phone lost".
PHONE_LOST_SEC = float(os.environ.get("PHONE_LOST_SEC", "600"))

DB_PATH = os.environ.get("BB_DB_PATH", "blackbox.db")

# Where scan files (.usdz, .json, .glb) are stored.
SCANS_DIR = os.environ.get("BB_SCANS_DIR", "scans")

# Feature flags
FEATURE_SCAN_COMPARE = _bool("FEATURE_SCAN_COMPARE", True)
FEATURE_MESH = _bool("FEATURE_MESH", True)
FEATURE_ATHENA = _bool("FEATURE_ATHENA", True)

# Athena chat assistant (Groq). Empty key = Athena answers "offline".
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
GROQ_MODEL = os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b")
# Athena Live (video call): a Groq model that can read pictures.
GROQ_VISION_MODEL = os.environ.get("GROQ_VISION_MODEL", "qwen/qwen3.8-27b")

# Nearest stairs per zone. Keep in sync with zoneExits in app/lib/config.dart.
ZONE_EXITS = {"A": "Stair 1, north side", "B": "Stair 1, north side", "C": "Stair 2, south side"}
