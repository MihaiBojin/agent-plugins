"""Configurations, suites and cases: what the testbed runs, and under which settings."""

import itertools
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / 'data'

# The order of the parts of a configuration's slug.
DIMENSIONS = ('comms', 'style', 'situation', 'signals', 'threads')

# The three thread booleans, as the five modes that differ. Focus and compact
# do nothing while threads are off, so that mode keeps their defaults.
THREAD_MODES = {
    'focus-compact': {'threads': 'on', 'focus': 'on', 'compact': 'on'},
    'focus': {'threads': 'on', 'focus': 'on', 'compact': 'off'},
    'compact': {'threads': 'on', 'focus': 'off', 'compact': 'on'},
    'threads-only': {'threads': 'on', 'focus': 'off', 'compact': 'off'},
    'off': {'threads': 'off', 'focus': 'on', 'compact': 'on'},
}
SIGNALS = ('off', 'intent', 'full')


def load_json(name):
    return json.loads((DATA / name).read_text(encoding='utf-8'))


def catalog(plugin):
    """The values each setting accepts, read from the plugin's own policy files."""
    policy = Path(plugin) / 'policy'

    def load(name):
        return json.loads((policy / name).read_text(encoding='utf-8'))

    return {
        'comms': list(load('profiles.json')),
        'style': ['ste' if key == 'ste-inspired' else key for key in load('language.json')],
        'situation': ['none', 'auto', *load('situations.json')],
        'signals': list(SIGNALS),
        'threads': list(THREAD_MODES),
        'guidelines': [entry['id'] for entry in load('guidelines.json')],
        'workflows': load('workflows.json'),
    }


def thread_mode(threads, focus, compact):
    if not threads:
        return 'off'
    for name, values in THREAD_MODES.items():
        if values == {'threads': 'on', 'focus': 'on' if focus else 'off', 'compact': 'on' if compact else 'off'}:
            return name
    raise ValueError('no thread mode matches')


def make_config(base, spec, values):
    """A configuration: the base with the spec's settings changed. 'disabled' turns the plugin off."""
    config = {**base, 'enabled': spec != 'disabled', 'guidelines': {}}
    if spec == 'disabled':
        return config
    for key, value in spec.items():
        if key == 'guidelines':
            unknown = set(value) - set(values['guidelines'])
            if unknown:
                raise ValueError(f'unknown guideline: {", ".join(sorted(unknown))}')
            config['guidelines'] = dict(value)
        elif key in DIMENSIONS:
            if value not in values[key]:
                raise ValueError(f'{key} has no value {value!r}; it takes {", ".join(values[key])}')
            config[key] = value
        else:
            raise ValueError(f'unknown setting: {key}')
    return config


def slug(config):
    """The configuration's directory name. Every setting is in it, in DIMENSIONS order."""
    if not config['enabled']:
        return 'disabled'
    name = '.'.join(config[key] for key in DIMENSIONS)
    for identifier, enabled in sorted(config['guidelines'].items()):
        name += ('.+' if enabled else '.-') + identifier
    return name


def product(base, values):
    """Every combination of the five settings, with no guideline overrides."""
    for combination in itertools.product(*(values[key] for key in DIMENSIONS)):
        yield make_config(base, dict(zip(DIMENSIONS, combination)), values)


def suite_configs(spec, base, values):
    if 'configs' in spec:
        return [make_config(base, item, values) for item in spec['configs']]
    if 'vary' in spec:
        return [make_config(base, {spec['vary']: value}, values) for value in values[spec['vary']]]
    if spec.get('workflows'):
        return [make_config(base, {'situation': item['situation'], 'signals': item['signaling']}, values)
                for item in values['workflows'].values()]
    if 'ablate' in spec:
        profile = {'comms': spec['ablate']}
        return [make_config(base, profile, values)] + [
            make_config(base, {**profile, 'guidelines': {identifier: True}}, values)
            for identifier in values['guidelines']]
    if spec.get('product'):
        return [make_config(base, 'disabled', values), *product(base, values)]
    raise ValueError('a suite needs configs, vary, workflows, ablate or product')


def suite_pairs(spec, base, values, scenarios):
    """The (scenario id, configuration) pairs one suite asks for."""
    if 'cases' in spec:
        return [(item['scenario'], make_config(base, item.get('config', {}), values)) for item in spec['cases']]
    wanted = spec['scenarios']
    ids = [item['id'] for item in scenarios if item['kind'] == 'task'] if wanted == ['*'] else wanted
    return [(scenario, config) for config in suite_configs(spec, base, values) for scenario in ids]


def parse_agent(text):
    """claude:MODEL[:EFFORT] or codex:MODEL[:EFFORT]."""
    parts = text.split(':')
    if len(parts) not in (2, 3) or parts[0] not in ('claude', 'codex') or not parts[1]:
        raise ValueError(f'agent must be claude:MODEL[:EFFORT] or codex:MODEL[:EFFORT], not {text!r}')
    effort = parts[2] if len(parts) == 3 and parts[2] else None
    label = '-'.join(part for part in (parts[0], parts[1], effort) if part)
    return {'client': parts[0], 'model': parts[1], 'effort': effort, 'label': label}


def cases(plugin, base, agents, suites, repeat=1, scenario_ids=(), config_match=(), limit=None):
    """Every case to run: an agent, a scenario, a configuration and a repeat, each once."""
    values = catalog(plugin)
    scenarios = load_json('scenarios.json')
    by_id = {item['id']: item for item in scenarios}
    definitions = load_json('suites.json')['suites']
    pairs = {}
    for name in suites:
        if name not in definitions:
            raise ValueError(f'unknown suite: {name}; known: {", ".join(definitions)}')
        for scenario, config in suite_pairs(definitions[name], base, values, scenarios):
            if scenario not in by_id:
                raise ValueError(f'suite {name} names unknown scenario {scenario}')
            key = (scenario, slug(config))
            pairs.setdefault(key, {'scenario': by_id[scenario], 'config': config, 'suites': []})
            if name not in pairs[key]['suites']:
                pairs[key]['suites'].append(name)
    selected = [pair for (scenario, name), pair in pairs.items()
                if (not scenario_ids or scenario in scenario_ids)
                and (not config_match or any(part in name for part in config_match))]
    if limit:
        selected = selected[:limit]
    return [{**pair, 'agent': agent, 'repeat': index,
             'key': f'{agent["label"]}/{pair["scenario"]["id"]}/{slug(pair["config"])}/r{index}'}
            for agent in agents for pair in selected for index in range(1, repeat + 1)]
