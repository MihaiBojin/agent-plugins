#!/bin/sh
# lefthook skips a pre-push command when the push changes no file, which is
# every tag push of a merged commit. It does not skip a script.
exec python3 -B testbed/e2e/pushed_tags.py
