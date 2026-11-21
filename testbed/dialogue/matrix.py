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
    """The values each setting accepts, read from the plugin's own policy files and settings.

    A plugin without the situation setting takes only situation none, and has no setup workflows."""
    import plugin as tested  # plugin imports this module, so the import waits for the call.
    policy = Path(plugin) / 'policy'

    def load(name):
        return json.loads((policy / name).read_text(encoding='utf-8'))

    situations = 'situation' in tested.settings_table(plugin)
    return {
        'comms': list(load('profiles.json')),
        'style': ['ste' if key == 'ste-inspired' else key for key in load('language.json')],
        'situation': ['none', 'auto', *load('situations.json')] if situations else ['none'],
        'signals': list(SIGNALS),
        'threads': list(THREAD_MODES),
        'guidelines': [entry['id'] for entry in load('guidelines.json')],
        'workflows': load('workflows.json') if (policy / 'workflows.json').exists() else {},
    }


def thread_mode(threads, focus, compact):
    if not threads:
        return 'off'
    for name, values in THREAD_MODES.items():
        if values == {'threads': 'on', 'focus': 'on' if focus else 'off', 'compact': 'on' if compact else 'off'}:
            return name
    raise ValueError('no thread mode matches')


class Unavailable(ValueError):
    """A configuration sets a situation, and the plugin under test has no situation setting."""


def available(specs, build):
    """build(spec) for each spec, leaving out the ones the plugin under test cannot run."""
    result = []
    for spec in specs:
        try:
            result.append(build(spec))
        except Unavailable:
            pass
    return result


def make_config(base, spec, values):
    """A configuration: the base with the spec's settings changed. 'disabled' turns the plugin off.

    `name` replaces the slug, for configurations too long to name by their settings. `drops` lists policy
    lines, as `FILE:LINE`, removed from the plugin's copy for this configuration only."""
    config = {**base, 'enabled': spec != 'disabled', 'guidelines': {}, 'drops': []}
    if spec == 'disabled':
        return config
    for key, value in spec.items():
        if key == 'name':
            config['name'] = value
        elif key == 'drops':
            config['drops'] = list(value)
        elif key == 'guidelines':
            unknown = set(value) - set(values['guidelines'])
            if unknown:
                raise ValueError(f'unknown guideline: {", ".join(sorted(unknown))}')
            config['guidelines'] = dict(value)
        elif key in DIMENSIONS:
            if key == 'situation' and value != 'none' and values['situation'] == ['none']:
                raise Unavailable(f'the plugin has no situation setting for {value!r}')
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
    if config.get('name'):
        return config['name']
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
        return available(spec['configs'], lambda item: make_config(base, item, values))
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


def rule_lines(plugin, path):
    """(line number, text) for every rule line of a policy file: not blank and not a heading."""
    lines = (Path(plugin) / path).read_text(encoding='utf-8').splitlines()
    return [(number, line) for number, line in enumerate(lines, 1) if line.strip() and not line.startswith('#')]


def leave_one_out(spec, base, values, plugin):
    """The reference configuration, then one configuration per unit with that unit removed.

    Each unit carries the scenarios where removing it can show; the reference runs on all of them."""
    reference = dict(spec['reference'])
    every = reference.pop('all_guidelines', False)
    if every:
        reference['guidelines'] = {identifier: True for identifier in values['guidelines']}
    name = spec.get('name', 'ref')
    result, union = [], []
    for unit in spec['units']:
        union += [scenario for scenario in unit['scenarios'] if scenario not in union]
        if unit['kind'] == 'guidelines':
            for identifier in values['guidelines']:
                if every or identifier in reference.get('guidelines', {}):
                    guidelines = {**reference.get('guidelines', {}), identifier: False}
                    config = make_config(base, {**reference, 'guidelines': guidelines, 'name': f'{name}.-{identifier}'},
                                         values)
                    result += [(scenario, config) for scenario in unit['scenarios']]
        elif unit['kind'] == 'lines':
            stem = Path(unit['file']).stem
            for number, text in rule_lines(plugin, unit['file']):
                config = make_config(base, {**reference, 'name': f'{name}.~{stem}{number}',
                                            'drops': [f'{unit["file"]}:{number}']}, values)
                config['drops_text'] = [text]
                result += [(scenario, config) for scenario in unit['scenarios']]
        else:
            raise ValueError(f'unknown unit kind: {unit["kind"]}')
    config = make_config(base, {**reference, 'name': name}, values)
    return [(scenario, config) for scenario in union] + result


def suite_pairs(spec, base, values, scenarios, plugin=None):
    """The (scenario id, configuration) pairs one suite asks for."""
    if 'leave_one_out' in spec:
        return leave_one_out(spec['leave_one_out'], base, values, plugin)
    if 'cases' in spec:
        return available(spec['cases'], lambda item: (item['scenario'], make_config(base, item.get('config', {}), values)))
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
        for scenario, config in suite_pairs(definitions[name], base, values, scenarios, plugin):
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
