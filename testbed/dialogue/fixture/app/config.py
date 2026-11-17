"""Load service settings from config.json."""

import json
import os

DEFAULTS = {"port": 8080, "cache": "none", "api_key_env": "INVENTORY_API_KEY"}


def load_config(path="config.json"):
    """Return the settings in the file at path, or DEFAULTS when the file is missing."""
    if not os.path.exists(path):
        return dict(DEFAULTS)
    with open(path, encoding="utf-8") as stream:
        return {**DEFAULTS, **json.load(stream)}
