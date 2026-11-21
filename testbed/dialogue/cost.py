"""Token prices, the cost of a turn, and the estimate for a plan."""

import json
from pathlib import Path

from matrix import load_json

KINDS = ('input', 'cache_write', 'cache_read', 'output')


def pricing():
    return load_json('pricing.json')


def rates(prices, agent):
    """USD per million tokens for the agent's model, or None when the model is not priced."""
    client = prices[agent['client']]
    model = client.get('aliases', {}).get(agent['model'], agent['model'])
    return client['models'].get(model)


def tokens(client, usage):
    """A client's usage report as uncached input, cache writes, cache reads and output."""
    usage = usage or {}
    if client == 'claude':
        return {'input': usage.get('input_tokens', 0),
                'cache_write': usage.get('cache_creation_input_tokens', 0),
                'cache_read': usage.get('cache_read_input_tokens', 0),
                'output': usage.get('output_tokens', 0)}
    cached = usage.get('cached_input_tokens', 0)
    # Codex reports reasoning tokens as a part of output_tokens.
    return {'input': usage.get('input_tokens', 0) - cached,
            'cache_write': usage.get('cache_write_input_tokens', 0),
            'cache_read': cached,
            'output': usage.get('output_tokens', 0)}


def price(model_rates, counts):
    if not model_rates:
        return None
    return sum(counts[kind] * model_rates[kind] for kind in KINDS) / 1_000_000


def calibrate(run_dir):
    """Mean tokens and seconds per turn for each client, measured in an earlier run."""
    totals = {}
    for path in Path(run_dir).glob('**/turns.json'):
        variant = json.loads((path.parent / 'variant.json').read_text(encoding='utf-8'))
        client = variant['agent']['client']
        entry = totals.setdefault(client, {kind: 0 for kind in (*KINDS, 'duration_s')} | {'turns': 0})
        for turn in json.loads(path.read_text(encoding='utf-8')):
            counts = tokens(client, turn.get('usage'))
            for kind in KINDS:
                entry[kind] += counts[kind]
            entry['duration_s'] += turn.get('duration_s') or 0
            entry['turns'] += 1
    return {client: {kind: entry[kind] / entry['turns'] for kind in (*KINDS, 'duration_s')}
            for client, entry in totals.items() if entry['turns']}


def estimate(cases, prices, measured=None, jobs=1):
    """Sessions, turns, tokens, dollars and hours for each agent in the plan."""
    rows = {}
    for case in cases:
        agent = case['agent']
        row = rows.setdefault(agent['label'], {'agent': agent, 'sessions': 0, 'turns': 0})
        row['sessions'] += 1
        row['turns'] += len(case['scenario']['turns'])
    for row in rows.values():
        client = row['agent']['client']
        profile = (measured or {}).get(client) or prices[client]['turn_tokens']
        row['profile'] = 'measured' if (measured or {}).get(client) else 'default'
        row['tokens'] = {kind: round(profile[kind] * row['turns']) for kind in KINDS}
        row['usd'] = price(rates(prices, row['agent']), row['tokens'])
        row['hours'] = profile['duration_s'] * row['turns'] / max(jobs, 1) / 3600
    return list(rows.values())
