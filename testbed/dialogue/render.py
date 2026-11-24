"""Render the policy of every configuration, without a model, and find what collapses, repeats or conflicts."""

from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import itertools
import json
from pathlib import Path
import re
import statistics
import tempfile

from clients import CLAUDE_INLINE_LIMIT
from matrix import DIMENSIONS, catalog, make_config, product, slug
import plugin
import report
from runner import codex_limit

SECTION_STARTS = (
    ('profile', ('## Communication profile', 'Communication profile is plain')),
    ('situation', ('## Situational framework', 'Situational mode:', 'No situational framework')),
    ('language', ('## Language standard',)),
    ('signals', ('## Communication signals',)),
    ('threads', ('## Thread protocol', 'Thread tracking is off')),
)

# Pairs of rules that cannot both be followed in one reply.
CONFLICTS = (
    ('numbered steps', 'Number ordered steps', 'Never use a numbered list',
     'STE scannable structure numbers ordered steps; the thread protocol forbids numbered lists'),
)

# Two ways to say the same thing. Each side starts from a fresh session after the setup commands.
COMMAND_PAIRS = (
    ('comms alias', [], [['set', 'comms', 'direct']], [['set', 'communication_profile', 'direct']]),
    ('style alias', [], [['set', 'style', 'ste']], [['set', 'language_standard', 'ste-inspired']]),
    ('signals alias', [], [['set', 'signals', 'full']], [['set', 'signaling', 'full']]),
    ('enable', [], [['enable']], [['set', 'enabled', 'on']]),
    ('disable', [['enable']], [['disable']], [['set', 'enabled', 'off']]),
    ('guideline on', [], [['guideline', 'enable', 'bluf']], [['guideline', 'on', 'bluf']]),
    ('guideline off', [], [['guideline', 'disable', 'bluf']], [['guideline', 'off', 'bluf']]),
    ('guideline group legacy', [], [['guideline', 'group', 'enable', 'risk']], [['guideline', 'group', 'risk', 'on']]),
    ('guidelines --all', [], [['guidelines', 'list']], [['guidelines', '--all']]),
    ('guidelines --group', [], [['guidelines', 'list', 'risk']], [['guidelines', '--group', 'risk']]),
    ('setup apply', [], [['setup', 'apply', '--comms', 'efficient', '--style', 'ste', '--signals', 'full']],
     [['set', 'comms', 'efficient'], ['set', 'style', 'ste'], ['set', 'signals', 'full']]),
)

LISTINGS = ('profiles', 'languages', 'situations', 'signals')


def render_one(plugin_path, config):
    """Each SessionStart hook part the configuration prints."""
    with tempfile.TemporaryDirectory() as state:
        plugin.seed(plugin_path, state, config)
        return plugin.render_parts(plugin_path, state)


def comparable(text, rules_only):
    """The policy without the session ID and the settings dump; rules_only also drops the profile's name."""
    lines = [line for line in text.replace(plugin.RENDER_SESSION, 'SESSION').splitlines()
             if not line.startswith('Effective settings: ')]
    if rules_only:
        lines = [re.sub(r'^## Communication profile: \S+', '## Communication profile: NAME', line) for line in lines]
    return '\n'.join(lines)


def digest(text):
    return hashlib.sha1(text.encode('utf-8')).hexdigest()[:10]


def sections(text):
    """Characters per policy section: header, profile, situation, language, signals, threads."""
    sizes, current = Counter(), 'header'
    for line in text.splitlines():
        for name, starts in SECTION_STARTS:
            if line.startswith(starts):
                current = name
        sizes[current] += len(line) + 1
    return sizes


def repeated_lines(text):
    """Lines of 40 characters or more that the policy prints more than once."""
    counts = Counter(line.strip() for line in text.splitlines() if len(line.strip()) >= 40)
    return {line: count for line, count in counts.items() if count > 1}


def conflicts(text):
    return [name for name, first, second, _ in CONFLICTS if first in text and second in text]


def command_pairs(plugin_path):
    """For each pair: do both sides leave the same saved settings and print the same output?"""
    rows = []
    for label, setup, first, second in COMMAND_PAIRS:
        sides = []
        for commands in (first, second):
            with tempfile.TemporaryDirectory() as state:
                try:
                    for command in setup:
                        plugin.tool(plugin_path, state, *command)
                    output = ''
                    for command in commands:
                        output = plugin.tool(plugin_path, state, *command)
                    saved = json.loads(plugin.tool(plugin_path, state, 'state'))
                    sides.append({'output': output, 'settings': saved['settings'], 'error': None})
                except RuntimeError as failure:
                    sides.append({'output': '', 'settings': None, 'error': str(failure)})
        errors = [side['error'] for side in sides if side['error']]
        rows.append({'pair': label, 'first': ' && '.join(' '.join(c) for c in first),
                     'second': ' && '.join(' '.join(c) for c in second),
                     'same_settings': None if errors else sides[0]['settings'] == sides[1]['settings'],
                     'same_output': None if errors else sides[0]['output'] == sides[1]['output'],
                     'error': '; '.join(errors)})
    return rows


def listing_coverage(plugin_path):
    """How many of the entries each listing command prints already appear in help."""
    with tempfile.TemporaryDirectory() as state:
        help_text = plugin.tool(plugin_path, state, 'help')
        rows = []
        for command in LISTINGS:
            if command == 'situations' and not (Path(plugin_path) / 'policy' / 'situations.json').exists():
                continue  # Dialogue 0.16.0 and later have no situations command.
            text = plugin.tool(plugin_path, state, command)
            names = re.findall(r'(?m)^\| ([\w-]+) \|', text) + re.findall(r'(?m)^- ([\w-]+):', text)
            names = [name for name in names
                     if name not in ('Profile', 'Standard', 'Situation') and not re.fullmatch('-+', name)]
            shown = ['ste' if name == 'ste-inspired' else name for name in names]
            rows.append({'command': command, 'entries': len(shown),
                         'in_help': sum(bool(re.search(rf'(?<![\w-]){re.escape(name)}(?![\w-])', help_text))
                                        for name in shown)})
    return rows


def skills(plugin_path):
    rows = []
    for path in sorted((Path(plugin_path) / 'skills').glob('*/SKILL.md')):
        text = path.read_text(encoding='utf-8')
        match = re.search(r'(?m)^description:\s*(.+)$', text)
        rows.append({'skill': path.parent.name, 'description': match.group(1).strip() if match else '',
                     'read_only': 'read-only' in text})
    return rows


def equivalences(classes, values):
    """For each setting and each two of its values: in how many contexts the policies are the same."""
    rows = []
    for index, key in enumerate(DIMENSIONS):
        others = [values[other] for other in DIMENSIONS if other != key]
        for first, second in itertools.combinations(values[key], 2):
            same = total = 0
            for context in itertools.product(*others):
                def lookup(value):
                    combination = list(context)
                    combination.insert(index, value)
                    return classes[tuple(combination)]
                total += 1
                same += lookup(first) == lookup(second)
            if same:
                rows.append({'setting': key, 'first': first, 'second': second, 'same': same, 'contexts': total})
    return rows


def render_all(plugin_source, out_dir, jobs):
    out_dir = Path(out_dir)
    with tempfile.TemporaryDirectory() as scratch:
        info = plugin.snapshot(plugin_source, Path(scratch) / 'dialogue')
        plugin_path = Path(info['path'])
        values = catalog(plugin_path)
        base = plugin.fresh_defaults(plugin_path)
        configs = [make_config(base, 'disabled', values), *product(base, values)]
        with ThreadPoolExecutor(max_workers=max(jobs, 1)) as pool:
            all_parts = list(pool.map(lambda config: render_one(plugin_path, config), configs))
        texts = ['\n\n'.join(parts) for parts in all_parts]
        pairs = command_pairs(plugin_path)
        coverage = listing_coverage(plugin_path)
        skill_rows = skills(plugin_path)
        limit = codex_limit(plugin_path)
    (out_dir / 'policies').mkdir(parents=True, exist_ok=True)
    rows, rules_classes, repeated, conflicted = [], {}, defaultdict(list), defaultdict(list)
    for config, text, parts in zip(configs, texts, all_parts):
        largest = max((len(part) for part in parts), default=0)
        name = slug(config)
        header = report.settings_line(config)
        (out_dir / 'policies' / f'{name}.md').write_text(
            f'<!-- dialogue policy for: {header} -->\n'
            f'<!-- {len(text):,} characters: what the SessionStart hook injects into a new claude session -->\n\n'
            f'{text}\n', encoding='utf-8')
        sizes = sections(text)
        exact, rules = digest(comparable(text, False)), digest(comparable(text, True))
        if config['enabled']:
            rules_classes[tuple(config[key] for key in DIMENSIONS)] = rules
        for line, count in repeated_lines(text).items():
            repeated[line].append((name, count))
        for conflict in conflicts(text):
            conflicted[conflict].append(name)
        rows.append({'config': name, 'enabled': config['enabled'],
                     **{key: config[key] for key in DIMENSIONS},
                     'chars': len(text), 'approx_tokens': round(len(text) / 4),
                     **{f'{section}_chars': sizes[section] for section in
                        ('header', 'profile', 'situation', 'language', 'signals', 'threads')},
                     'hook_parts': len(parts), 'largest_part_chars': largest,
                     'over_claude_inline_limit': largest > CLAUDE_INLINE_LIMIT,
                     'over_codex_limit': bool(limit and largest > limit),
                     'repeated_lines': sum(count - 1 for count in repeated_lines(text).values()),
                     'conflicts': ' '.join(conflicts(text)), 'exact_class': exact, 'rules_class': rules})
    with open(out_dir / 'index.csv', 'w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    analysis = {'plugin': info, 'base': base, 'values': {key: values[key] for key in DIMENSIONS},
                'equivalences': equivalences(rules_classes, values), 'command_pairs': pairs,
                'listing_coverage': coverage, 'skills': skill_rows, 'codex_limit': limit}
    (out_dir / 'report.md').write_text(
        summary(rows, analysis, repeated, conflicted) + '\n', encoding='utf-8')
    report.write_json(out_dir / 'analysis.json', analysis)
    return rows


def summary(rows, analysis, repeated, conflicted):
    enabled = [row for row in rows if row['enabled']]
    chars = [row['chars'] for row in enabled]
    base = analysis['base']
    base_row = next(row for row in enabled if all(row[key] == base[key] for key in DIMENSIONS))
    over_claude = sum(row['over_claude_inline_limit'] for row in enabled)
    over_codex = sum(row['over_codex_limit'] for row in enabled)
    info = analysis['plugin']
    lines = [
        '# Rendered policies', '',
        f'dialogue {info["version"]} from `{info["source"]}` at `{(info["git_commit"] or "")[:12]}`'
        f'{" with uncommitted changes" if info["git_dirty"] else ""}. '
        f'Every combination of {", ".join(DIMENSIONS)}: {len(enabled)} enabled configurations and the disabled one. '
        'Each policy is in `policies/<config>.md`; `index.csv` has one row per configuration.', '',
        '## Distinct policies', '',
        f'- Exact text, ignoring the session ID and the settings dump: '
        f'{len({row["exact_class"] for row in enabled})} distinct policies.',
        f'- Ignoring the profile name as well: {len({row["rules_class"] for row in enabled})} distinct policies.', '',
        '## Setting values that produce the same policy', '',
        'A row means the two values give the same rules in that many combinations of the other settings. '
        'A value that matches another in every context is a candidate for removal.', '',
        '| Setting | Value | Same as | Contexts |', '| --- | --- | --- | --- |']
    for row in analysis['equivalences']:
        lines.append(f'| {row["setting"]} | `{row["first"]}` | `{row["second"]}` | {row["same"]} of {row["contexts"]} |')
    if not analysis['equivalences']:
        lines.append('| none | | | |')
    lines += [
        '', '## Size', '',
        f'- Enabled policies run from {min(chars):,} to {max(chars):,} characters, median {statistics.median(chars):,.0f}.',
        f'- The base configuration (`{base_row["config"]}`, what `enable` gives a fresh session) '
        f'is {base_row["chars"]:,} characters.',
        f'- The policy is printed in {max(row["hook_parts"] for row in enabled)} hook parts; the largest part is '
        f'{max(row["largest_part_chars"] for row in enabled):,} characters.',
        f'- {over_claude} of {len(enabled)} have a part over the {CLAUDE_INLINE_LIMIT:,}-character limit up to which '
        'Claude Code puts each hook\'s context into the conversation. Above it, the model gets a 2 KB preview and a '
        'file path.',
        f'- {over_codex} of {len(enabled)} exceed the {analysis["codex_limit"] or "unset"}-character '
        '`additionalContextLimit` in `hooks/codex.json`.',
        '- A session with open threads adds its thread listing on top of these sizes.', '',
        'Mean characters by setting value:', '',
        '| Setting | Value | Mean characters | Over the Claude Code limit |', '| --- | --- | --- | --- |']
    for key in DIMENSIONS:
        for value in analysis['values'][key]:
            subset = [row for row in enabled if row[key] == value]
            lines.append(f'| {key} | `{value}` | {statistics.mean(row["chars"] for row in subset):,.0f} | '
                         f'{sum(row["over_claude_inline_limit"] for row in subset)} of {len(subset)} |')
    lines += ['', '## Lines printed more than once in one policy', '']
    if repeated:
        lines += ['| Line | Configurations | Most copies |', '| --- | --- | --- |']
        for line, where in sorted(repeated.items(), key=lambda item: -len(item[1])):
            shown = line.replace('|', '\\|')
            lines.append(f'| {shown[:120]} | {len(where)} | {max(count for _, count in where)} |')
    else:
        lines.append('None.')
    lines += ['', '## Rules that conflict', '']
    for name, first, second, note in CONFLICTS:
        lines.append(f'- **{name}**: {note}. Both rules are in {len(conflicted.get(name, []))} configurations.')
    lines += ['', '## Command forms that do the same thing', '',
              'Each side runs on a fresh, disabled session. Same settings means the saved settings match '
              'afterwards; same output compares what the last command of each side printed.', '',
              '| Pair | First | Second | Same settings | Same output | Error |', '| --- | --- | --- | --- | --- | --- |']
    for row in analysis['command_pairs']:
        lines.append(f'| {row["pair"]} | `{row["first"]}` | `{row["second"]}` | {row["same_settings"]} | '
                     f'{row["same_output"]} | {row["error"]} |')
    lines += ['', '## Listing commands and help', '',
              '| Command | Entries | Also named in `help` |', '| --- | --- | --- |']
    for row in analysis['listing_coverage']:
        lines.append(f'| `{row["command"]}` | {row["entries"]} | {row["in_help"]} |')
    read_only = [row for row in analysis['skills'] if row['read_only']]
    lines += ['', '## Commands', '',
              f'The plugin has {len(analysis["skills"])} commands; {len(read_only)} say they are read-only.', '',
              '| Command | Read-only | Description |', '| --- | --- | --- |']
    for row in analysis['skills']:
        lines.append(f'| `{row["skill"]}` | {"yes" if row["read_only"] else ""} | {row["description"]} |')
    return '\n'.join(lines)
