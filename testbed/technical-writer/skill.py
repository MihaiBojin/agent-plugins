"""The write-technical-prose skill under test: its rules, their groups, and plugin copies with rules removed."""

import json
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent
NAME = 'write-technical-prose'
SKILL = Path('skills') / NAME / 'SKILL.md'
RULE = re.compile(r'^### `([a-z_]+)`\s*$')
HEADING = re.compile(r'^(#{1,3}) ')
# Sections that hold guidance but no rule IDs, removed as one unit each.
SECTIONS = {'dials': 'The dials'}


def lines_of(plugin):
    return (Path(plugin) / SKILL).read_text(encoding='utf-8').splitlines(keepends=True)


def rules(plugin):
    """Each `### \\`id\\`` rule: its ID, the `##` section it sits in, its text, and its line span [start, end)."""
    lines = lines_of(plugin)
    found, section = [], None
    for index, line in enumerate(lines):
        heading = HEADING.match(line)
        if heading and heading.group(1) == '##':
            section = line[3:].strip()
        match = RULE.match(line)
        if match:
            end = next((later for later in range(index + 1, len(lines)) if HEADING.match(lines[later])), len(lines))
            found.append({'id': match.group(1), 'section': section, 'start': index, 'end': end,
                          'text': ''.join(lines[index + 1:end]).strip()})
    return found


def section_span(plugin, title):
    """The [start, end) lines of a `## title` section, its heading included."""
    lines = lines_of(plugin)
    start = next(index for index, line in enumerate(lines) if line.strip() == f'## {title}')
    end = next((later for later in range(start + 1, len(lines)) if lines[later].startswith(('# ', '## '))),
               len(lines))
    return start, end


def groups():
    return json.loads((HERE / 'data' / 'groups.json').read_text(encoding='utf-8'))


def units(plugin, kind):
    """Configuration name to the line spans it removes. `off` runs without the plugin and `full` with all of it.

    kind `groups` removes one group of rules, or one section, per configuration, as `*NAME`; kind `rules` removes
    one rule, as `-ID`."""
    by_id = {rule['id']: (rule['start'], rule['end']) for rule in rules(plugin)}
    result = {'off': None, 'full': []}
    if kind in ('groups', 'all'):
        for name, members in groups().items():
            result[f'*{name}'] = [by_id[member] for member in members]
        for name, title in SECTIONS.items():
            result[f'*{name}'] = [section_span(plugin, title)]
    if kind in ('rules', 'all'):
        for identifier, span in by_id.items():
            result[f'-{identifier}'] = [span]
    return result


def patched(plugin, spans, destination):
    """A copy of the plugin whose SKILL.md lacks the given line spans."""
    shutil.copytree(plugin, destination, ignore=shutil.ignore_patterns('__pycache__', 'evals', '.DS_Store'))
    lines = lines_of(plugin)
    dropped = {index for start, end in spans for index in range(start, end)}
    (Path(destination) / SKILL).write_text(''.join(line for index, line in enumerate(lines) if index not in dropped),
                                           encoding='utf-8')
    return destination
