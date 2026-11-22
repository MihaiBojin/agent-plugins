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

    A plugin without the situation setting takes only situation none."""
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
    if 'ablate' in spec:
        profile = {'comms': spec['ablate']}
        return [make_config(base, profile, values)] + [
            make_config(base, {**profile, 'guidelines': {identifier: True}}, values)
            for identifier in values['guidelines']]
    if spec.get('product'):
        return [make_config(base, 'disabled', values), *product(base, values)]
    raise ValueError('a suite needs configs, vary, ablate or product')


def rule_lines(plugin, path):
    """(line number, text) for every rule line of a policy file: not blank and not a heading."""
    lines = (Path(plugin) / path).read_text(encoding='utf-8').splitlines()
    return [(number, line) for number, line in enumerate(lines, 1) if line.strip() and not line.startswith('#')]


def paragraphs(numbered):
    """Rule lines split where the file has a blank line or a heading between them, as lists of (number, text)."""
    blocks = []
    for number, text in numbered:
        if blocks and number == blocks[-1][-1][0] + 1:
            blocks[-1].append((number, text))
        else:
            blocks.append([(number, text)])
    return blocks


def leave_one_out(spec, base, values, plugin, units=None, together=False, sets=None):
    """The reference configuration, then one configuration per unit with that unit removed.

    Each unit carries the scenarios where removing it can show; the reference runs on all of them. A unit with
    `"group": true` removes a group at a time instead of one rule: the guidelines of one type, as
    `REF.*type-TYPE`, or one paragraph of rule lines, as `REF.*STEMFIRST-LAST`. `sets` maps a name to units of the
    suite, such as `{"half": ["ref.-bluf", "ref.~threads3"]}`, and replaces the units with one `REF.*NAME` per set,
    on the scenarios of all its members. `units` keeps only the units with those configuration names. `together`
    adds one configuration, `REF.*together`, that removes every kept unit at once, on all their scenarios, for
    rules that only matter when another is gone."""
    reference = dict(spec['reference'])
    every = reference.pop('all_guidelines', False)
    if every:
        reference['guidelines'] = {identifier: True for identifier in values['guidelines']}
    name = spec.get('name', 'ref')

    def removing(label, guidelines, lines, members=None):
        """The reference with these guidelines off and these (drop, text) lines deleted."""
        config = make_config(base, {**reference, 'name': label, 'drops': [drop for drop, _ in lines],
                                    'guidelines': {**reference.get('guidelines', {}),
                                                   **{identifier: False for identifier in guidelines}}}, values)
        if lines:
            config['drops_text'] = [text for _, text in lines]
        if members is not None:
            config['together'] = members
        return config

    kept = []  # (scenarios, guidelines removed, (drop, text) lines removed, configuration)
    for unit in spec['units']:
        grouped = unit.get('group', False)
        if unit['kind'] == 'guidelines':
            chosen = [identifier for identifier in values['guidelines']
                      if every or identifier in reference.get('guidelines', {})]
            if grouped:
                entries = json.loads((Path(plugin) / 'policy' / 'guidelines.json').read_text(encoding='utf-8'))
                types = {entry['id']: entry['type'] for entry in entries}
                groups = {}
                for identifier in chosen:
                    groups.setdefault(types[identifier], []).append(identifier)
                for kind, group in groups.items():
                    kept.append((unit['scenarios'], group, [], removing(f'{name}.*type-{kind}', group, [], group)))
            else:
                for identifier in chosen:
                    kept.append((unit['scenarios'], [identifier], [],
                                 removing(f'{name}.-{identifier}', [identifier], [])))
        elif unit['kind'] == 'lines':
            stem = Path(unit['file']).stem
            numbered = rule_lines(plugin, unit['file'])
            blocks = paragraphs(numbered) if grouped else [[line] for line in numbered]
            for block in blocks:
                lines = [(f'{unit["file"]}:{number}', text) for number, text in block]
                if grouped:
                    label = f'{name}.*{stem}{block[0][0]}-{block[-1][0]}'
                    config = removing(label, [], lines, [f'{stem}{number}' for number, _ in block])
                else:
                    config = removing(f'{name}.~{stem}{block[0][0]}', [], lines)
                kept.append((unit['scenarios'], [], lines, config))
        else:
            raise ValueError(f'unknown unit kind: {unit["kind"]}')
    if sets is not None:
        by_slug = {slug(item[3]): item for item in kept}
        unknown = {member for members in sets.values() for member in members} - set(by_slug)
        if unknown:
            raise ValueError(f'unknown ablation unit in a set: {", ".join(sorted(unknown))}')
        grouped = []
        for label, members in sets.items():
            items = [by_slug[member] for member in members]
            scenarios = []
            for item in items:
                scenarios += [scenario for scenario in item[0] if scenario not in scenarios]
            guidelines = [identifier for item in items for identifier in item[1]]
            lines = [line for item in items for line in item[2]]
            grouped.append((scenarios, guidelines, lines, removing(f'{name}.*{label}', guidelines, lines, members)))
        kept = grouped
    if units is not None:
        unknown = set(units) - {slug(config) for *_, config in kept}
        if unknown:
            raise ValueError(f'unknown ablation unit: {", ".join(sorted(unknown))}')
        kept = [item for item in kept if slug(item[3]) in units]
    union, result = [], []
    for scenarios, _, _, config in kept:
        union += [scenario for scenario in scenarios if scenario not in union]
        result += [(scenario, config) for scenario in scenarios]
    if together and kept:
        config = removing(f'{name}.*together', [identifier for item in kept for identifier in item[1]],
                          [line for item in kept for line in item[2]], [slug(item[3]) for item in kept])
        result += [(scenario, config) for scenario in union]
    config = make_config(base, {**reference, 'name': name}, values)
    return [(scenario, config) for scenario in union] + result


def suite_pairs(spec, base, values, scenarios, plugin=None, units=None, together=False, sets=None):
    """The (scenario id, configuration) pairs one suite asks for."""
    if 'leave_one_out' in spec:
        return leave_one_out(spec['leave_one_out'], base, values, plugin, units, together, sets)
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


def cases(plugin, base, agents, suites, repeat=1, scenario_ids=(), config_match=(), limit=None, units=None,
          together=False, sets=None):
    """Every case to run: an agent, a scenario, a configuration and a repeat, each once."""
    values = catalog(plugin)
    scenarios = load_json('scenarios.json')
    by_id = {item['id']: item for item in scenarios}
    definitions = load_json('suites.json')['suites']
    pairs = {}
    for name in suites:
        if name not in definitions:
            raise ValueError(f'unknown suite: {name}; known: {", ".join(definitions)}')
        for scenario, config in suite_pairs(definitions[name], base, values, scenarios, plugin, units, together,
                                            sets):
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
