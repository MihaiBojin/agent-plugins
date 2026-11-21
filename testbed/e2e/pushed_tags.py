"""Run the e2e cases of each plugin whose release tag is being pushed.

Git's pre-push hook writes one line per pushed ref to stdin. A release tag here is
`refs/tags/<plugin>/v<version>`. The cases run against the plugin as the tagged commit has
it, which the working tree may not match.
"""

from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RELEASE_TAG = re.compile(r'refs/tags/([^/]+)/v\d')


def released(lines):
    """The plugin and the object ID of every release tag in the hook's input, without deleted tags."""
    found = {}
    for line in lines:
        parts = line.split()
        if len(parts) != 4:
            continue
        local_ref, local_id = parts[0], parts[1]
        match = RELEASE_TAG.match(local_ref)
        if match and set(local_id) != {'0'}:
            found[match.group(1)] = local_id
    return sorted(found.items())


def export(root, object_id, plugin, destination):
    """Unpack `plugins/<plugin>` as the tagged commit has it. Returns None when the commit has no such plugin."""
    archive = subprocess.run(['git', '-C', str(root), 'archive', object_id, f'plugins/{plugin}'],
                             capture_output=True)
    if archive.returncode != 0:
        return None
    subprocess.run(['tar', '-x', '-C', str(destination)], input=archive.stdout, check=True)
    return Path(destination) / 'plugins' / plugin


def main():
    failed = []
    for plugin, object_id in released(sys.stdin.read().splitlines()):
        with tempfile.TemporaryDirectory(prefix='e2e-tag-') as scratch:
            directory = export(ROOT, object_id, plugin, scratch)
            if directory is None:
                print(f'{plugin}: the tagged commit has no plugins/{plugin}, so no e2e cases ran')
                continue
            print(f'{plugin}: running the e2e cases of {object_id[:7]}', flush=True)
            if subprocess.run(['make', '-C', str(ROOT), 'e2e', f'PLUGIN_DIR={directory}']).returncode != 0:
                failed.append(plugin)
    if failed:
        print(f'The e2e cases failed for {", ".join(failed)}, so the push stops here. '
              'To push without them, set LEFTHOOK=0 for that one command.')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
