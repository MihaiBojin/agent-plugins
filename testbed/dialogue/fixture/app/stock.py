"""Stock levels and reorder rules."""


def reorder_needed(level, threshold):
    """True when stock is at or below the threshold."""
    return level < threshold
