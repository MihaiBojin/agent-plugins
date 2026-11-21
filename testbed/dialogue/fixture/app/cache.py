"""Cache for supplier lookups.

Nothing is cached yet. The storage is not chosen: one JSON file per key, or a
single SQLite file.
"""


def get(key):
    return None


def put(key, value):
    pass
