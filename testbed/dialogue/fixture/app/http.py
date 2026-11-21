"""Outgoing calls to the supplier API."""

import time
import urllib.error
import urllib.request


def fetch(url, retries=3):
    """GET url and return the body. Connection errors are retried; HTTP errors are raised."""
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url) as response:
                return response.read()
        except urllib.error.URLError as error:
            if isinstance(error, urllib.error.HTTPError):
                raise
            time.sleep(2**attempt)
    raise RuntimeError(f"could not reach {url} after {retries} attempts")
