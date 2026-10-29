"""Validated JSON state, serialized across processes and replaced atomically."""

from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import tempfile
import time

MISSING = object()

SETTINGS = {
    'enabled': (False, 'Apply dialogue behavior in this session.'),
    'threads': (True, 'Track decisions with stable IDs and saved state.'),
    'focus': (True, 'Finish the active issue before presenting unrelated issues; requires threads.'),
    'compact': (True, 'Show relevant threads and count other open threads; requires threads.'),
    'response_style': ('pyramid', 'pyramid: answer, reasons, evidence; plain: no additional style instructions.'),
}


def setting_value(key, value):
    if key not in SETTINGS:
        raise ValueError(f'unknown setting: {key}')
    if key == 'response_style':
        if value not in ('pyramid', 'plain'):
            raise ValueError('response_style must be pyramid or plain')
        return value
    if value in ('on', 'true'):
        return True
    if value in ('off', 'false'):
        return False
    raise ValueError(f'{key} must be on or off')


def validate_settings(value):
    if not isinstance(value, dict) or set(value) != set(SETTINGS):
        raise ValueError('invalid settings keys')
    for key, item in value.items():
        if key == 'response_style':
            if item not in ('pyramid', 'plain'):
                raise ValueError('invalid response_style')
        elif type(item) is not bool:
            raise ValueError(f'invalid boolean setting: {key}')
    return value


def unique_keys(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f'duplicate JSON key: {key}')
        value[key] = item
    return value


def read_json(path):
    try:
        with path.open(encoding='utf-8') as stream:
            return json.load(stream, object_pairs_hook=unique_keys)
    except FileNotFoundError:
        return MISSING
    except (ValueError, UnicodeError) as error:
        raise ValueError(f'cannot read {path}: {error}; state was not reset') from error


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.dialogue-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def state_root():
    configured = os.environ.get('DIALOGUE_STATE_DIR')
    if configured:
        return Path(configured).expanduser().resolve()
    base = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local' / 'state')))
    return base / 'dialogue'


@contextmanager
def locked(root):
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (root / '.lock').open('a+b') as stream:
        if os.name == 'nt':
            import msvcrt
            stream.seek(0, os.SEEK_END)
            if stream.tell() == 0:
                stream.write(b'0')
                stream.flush()
            lock = lambda: msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            unlock = lambda: msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            lock = lambda: fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            unlock = lambda: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        deadline = time.monotonic() + 10
        while True:
            try:
                stream.seek(0)
                lock()
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise ValueError('state lock timed out; another dialogue command is still running')
                time.sleep(0.02)
        try:
            yield
        finally:
            stream.seek(0)
            unlock()


class Store:
    def __init__(self, client, session):
        if client not in ('claude', 'codex'):
            raise ValueError('client must be claude or codex')
        if not isinstance(session, str) or not session or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}', session):
            raise ValueError('a valid session ID is required; never guess a session ID')
        self.root = state_root()
        self.path = self.root / 'sessions' / client / f'{session}.json'
        self.client, self.session = client, session

    def defaults(self):
        data = read_json(self.root / 'defaults.json')
        return validate_settings(data if data is not MISSING else {k: v[0] for k, v in SETTINGS.items()})

    def read(self):
        data = read_json(self.path)
        if data is MISSING:
            return {'version': 1, 'client': self.client, 'session': self.session,
                    'settings': self.defaults(), 'active': None, 'threads': {}}
        from threads import validate_threads
        if (not isinstance(data, dict) or set(data) != {'version', 'client', 'session', 'settings', 'active', 'threads'}
                or data.get('version') != 1
                or data.get('client') != self.client or data.get('session') != self.session):
            raise ValueError(f'invalid session state: {self.path}; state was not reset')
        validate_settings(data.get('settings'))
        validate_threads(data)
        return data

    def change(self, action):
        with locked(self.root):
            data = self.read()
            result = action(data)
            save_json(self.path, data)
            return data, result

    def change_default(self, key, value):
        with locked(self.root):
            defaults = self.defaults()
            defaults[key] = value
            save_json(self.root / 'defaults.json', defaults)
