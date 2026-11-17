"""Files for one variant (transcript.md, metrics.json), and the run's index of every variant."""

import csv
import json
from pathlib import Path
import re

from clients import CLAUDE_INLINE_LIMIT, narration, reads_policy_file
from metrics import turn_metrics

SETTING_COLUMNS = ('comms', 'style', 'situation', 'signals', 'threads')
METRIC_COLUMNS = ('words', 'sentences', 'mean_sentence_words', 'long_sentences', 'headings', 'bullets',
                  'numbered_items', 'tables', 'em_dashes', 'contractions', 'decisions_heading',
                  'thread_headings', 'option_lines', 'recommended', 'footer', 'markers', 'framework',
                  'narration_blocks', 'tool_calls', 'failed_tool_calls', 'dialogue_calls', 'dialogue_ops',
                  'threads_open', 'threads_closed', 'options', 'enabled_after', 'comms_after',
                  'situation_after')


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def settings_line(config):
    if not config['enabled']:
        return 'dialogue disabled'
    line = ', '.join(f'{key}={config[key]}' for key in SETTING_COLUMNS)
    if config['guidelines']:
        line += ', guidelines ' + ' '.join(('+' if on else '-') + key for key, on in sorted(config['guidelines'].items()))
    return line


def policy_delivery(variant, short=False):
    """How the policy reached the model: inline, or a preview the agent did or did not follow to the file."""
    read = variant.get('policy_read')
    if not variant.get('policy_chars'):
        return 'none' if short else 'none: dialogue is disabled when the session starts'
    if read is None:
        if short:
            return 'over limit' if variant['policy_notes'] else 'inline'
        return '; '.join(variant['policy_notes']) or 'delivered inline'
    turn = variant.get('policy_read_turn')
    if short:
        return f'preview, read t{turn}' if read else 'preview, unread'
    return '; '.join(variant['policy_notes']) + (
        f'; the agent read the full file in turn {turn}' if read else '; the agent never read the full file')


def fence(text):
    """A code fence longer than any backtick run inside text."""
    longest = max((len(run) for run in re.findall('`+', text)), default=0)
    return '`' * max(4, longest + 1)


def tool_line(item):
    shown = item['input'] if isinstance(item['input'], str) else json.dumps(item['input'], ensure_ascii=False)
    shown = shown.replace('`', "'").replace('\n', ' ')[:300]
    status = ' (failed)' if item['is_error'] else ''
    return f'- **{item["name"]}**{status}: `{shown}`'


def transcript(variant, turns):
    """The conversation of one variant, readable top to bottom."""
    agent, config = variant['agent'], variant['config']
    lines = [f'# {variant["scenario"]["id"]} / {variant["slug"]} / {agent["label"]} / repeat {variant["repeat"]}', '',
             '| Field | Value |', '| --- | --- |',
             f'| Agent | {agent["client"]} `{agent["model"]}` effort `{agent["effort"] or "default"}` |',
             f'| Scenario | `{variant["scenario"]["id"]}`: {variant["scenario"]["probes"]} |',
             f'| Settings | {settings_line(config)} |',
             f'| Suites | {", ".join(variant["suites"])} |',
             f'| Plugin | dialogue {variant["plugin"]["version"]} at `{(variant["plugin"]["git_commit"] or "")[:12]}`'
             f'{" with uncommitted changes" if variant["plugin"]["git_dirty"] else ""} |',
             f'| Policy | {variant["policy_chars"]:,} characters; {policy_delivery(variant)} |',
             f'| Status | {variant["status"]}{": " + variant["error"] if variant.get("error") else ""} |',
             f'| Cost | {format_usd(variant.get("cost_usd"))} over {len(turns)} turns |', '']
    for number, turn in enumerate(turns, 1):
        lines += [f'## Turn {number}', '', '**User:**', '', quote(turn['sent']), '']
        working = narration(turn['items'])
        tools = [item for item in turn['items'] if item['type'] == 'tool']
        if working or tools:
            lines += ['**While working:**', '']
            for item in turn['items']:
                if item['type'] == 'tool':
                    lines.append(tool_line(item))
                elif item['text'] in working:
                    lines.append(f'- said: {item["text"].strip()[:500]}')
            lines.append('')
        reply = turn.get('reply') or ''
        marker = fence(reply)
        lines += ['**Reply:**', '', f'{marker}markdown', reply, marker, '']
        if turn.get('error'):
            lines += [f'**Error:** {turn["error"]}', '']
        state = turn.get('state_after') or {}
        threads = state.get('threads') or {}
        if threads:
            lines += ['**Threads after this turn:**', '']
            for identifier, item in sorted(threads.items(), key=lambda pair: [int(p) for p in pair[0].split('.')]):
                options = ' '.join(f'{letter}:{option["status"]}' for letter, option in item['options'].items())
                lines.append(f'- {identifier}/ {item["status"]}: {item["title"]}' + (f' [{options}]' if options else ''))
            lines.append('')
    return '\n'.join(lines)


def quote(text):
    return '\n'.join('> ' + line for line in text.splitlines()) or '>'


def format_usd(value):
    return 'unknown' if value is None else f'${value:.4f}'


def write_case(case_dir, terms):
    """transcript.md and metrics.json for one variant, from what the run saved."""
    case_dir = Path(case_dir)
    variant = read_json(case_dir / 'variant.json')
    turns = read_json(case_dir / 'turns.json')
    if variant['agent']['client'] == 'claude':
        # Over the inline limit the model sees a preview and a path; did it open the file?
        read = [number for number, turn in enumerate(turns, 1) if any(map(reads_policy_file, turn['items']))]
        variant['policy_read_turn'] = read[0] if read else None
        variant['policy_read'] = bool(read) if variant['policy_chars'] > CLAUDE_INLINE_LIMIT else None
        write_json(case_dir / 'variant.json', variant)
    metrics = [turn_metrics(turn, terms) for turn in turns]
    write_json(case_dir / 'metrics.json', metrics)
    (case_dir / 'transcript.md').write_text(transcript(variant, turns) + '\n', encoding='utf-8')
    return variant, turns, metrics


def case_dirs(run_dir):
    return sorted(path.parent for path in Path(run_dir).glob('cases/**/variant.json'))


def write_index(run_dir):
    """index.csv: one row per turn of every variant. summary.md: one row per variant, with links."""
    run_dir = Path(run_dir)
    terms = read_json(run_dir / 'run.json')['terms']
    rows, variants = [], []
    for case_dir in case_dirs(run_dir):
        variant, turns, metrics = write_case(case_dir, terms)
        variants.append((case_dir, variant, metrics))
        for number, values in enumerate(metrics, 1):
            rows.append({
                'agent': variant['agent']['label'], 'client': variant['agent']['client'],
                'model': variant['agent']['model'], 'effort': variant['agent']['effort'] or '',
                'scenario': variant['scenario']['id'], 'config': variant['slug'],
                'enabled': variant['config']['enabled'],
                **{key: variant['config'][key] for key in SETTING_COLUMNS},
                'guidelines': ' '.join(('+' if on else '-') + key
                                       for key, on in sorted(variant['config']['guidelines'].items())),
                'repeat': variant['repeat'], 'turn': number, 'status': variant['status'],
                'policy_chars': variant['policy_chars'], 'policy_delivery': policy_delivery(variant, short=True),
                'cost_usd': turns[number - 1].get('cost_usd'),
                'duration_s': turns[number - 1].get('duration_s'),
                **{key: values[key] for key in METRIC_COLUMNS},
                'path': str(case_dir.relative_to(run_dir)),
            })
    if rows:
        with open(run_dir / 'index.csv', 'w', newline='', encoding='utf-8') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    (run_dir / 'summary.md').write_text(summary(run_dir, variants) + '\n', encoding='utf-8')
    return len(variants), len(rows)


def per_turn(metrics, key):
    return '/'.join(str(values[key]) if values[key] not in (None, '') else '-' for values in metrics)


def summary(run_dir, variants):
    """A table per scenario. Each row is one variant: its numbers and a link to its own transcript."""
    lines = ['# Run summary', '',
             'Each row is one variant. Numbers separated by `/` are per turn. The replies are in each '
             "variant's transcript.md; this file holds no reply text.", '']
    by_scenario = {}
    for case_dir, variant, metrics in variants:
        by_scenario.setdefault(variant['scenario']['id'], []).append((case_dir, variant, metrics))
    for scenario, entries in sorted(by_scenario.items()):
        lines += [f'## {scenario}', '', f'{entries[0][1]["scenario"]["probes"]}.', '',
                  '| Agent | Settings | Status | Policy | Words | Numbered | Tables | Decisions | Open/closed threads '
                  '| Markers | Framework | Dialogue calls | Cost | Transcript |',
                  '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |']
        for case_dir, variant, metrics in sorted(entries, key=lambda entry: (entry[1]['agent']['label'], entry[1]['slug'])):
            last = metrics[-1] if metrics else {}
            link = (case_dir / 'transcript.md').relative_to(run_dir)
            lines.append(' | '.join([
                f'| {variant["agent"]["label"]}', f'`{variant["slug"]}` r{variant["repeat"]}', variant['status'],
                policy_delivery(variant, short=True), per_turn(metrics, 'words'), per_turn(metrics, 'numbered_items'), per_turn(metrics, 'tables'),
                per_turn(metrics, 'thread_headings'),
                f'{last.get("threads_open", 0)}/{last.get("threads_closed", 0)}',
                ' '.join(sorted({part for values in metrics for part in values['markers'].split()})) or '-',
                ' '.join(sorted({values['framework'] for values in metrics if values['framework']})) or '-',
                per_turn(metrics, 'dialogue_calls'), format_usd(variant.get('cost_usd')),
                f'[transcript]({link}) |']))
        lines.append('')
    return '\n'.join(lines)
