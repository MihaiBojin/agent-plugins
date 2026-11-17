#!/usr/bin/env python3
"""Run the dialogue plugin under every setting it has, with claude -p and codex exec, and keep what comes out.

  render   Render the policy of every configuration. No model, no cost.
  plan     List the cases a run would execute, and estimate tokens, dollars and time.
  run      Execute the cases. Each variant gets its own directory under out/.
  report   Rebuild the transcripts, metrics and index of a run directory.
"""

import argparse
from datetime import datetime
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True

import cost  # noqa: E402
import matrix  # noqa: E402
import plugin  # noqa: E402
import report  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = HERE / 'out'
DEFAULT_PLUGIN = HERE.parents[1] / 'plugins' / 'dialogue'
DEFAULT_AGENTS = ('claude:haiku', 'codex:gpt-6-luna:low')
DEFAULT_WORK = Path(os.environ.get('DIALOGUE_TESTBED_WORK') or Path(tempfile.gettempdir()) / 'dialogue-testbed')


def new_out_dir(kind):
    path = OUT / f'{datetime.now().strftime("%Y%m%d-%H%M%S")}-{kind}'
    path.mkdir(parents=True)
    latest = OUT / f'latest-{kind}'
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(path.name)
    return path


def selection(args):
    agents = [matrix.parse_agent(text) for text in (args.agent or DEFAULT_AGENTS)]
    suites = list(args.suite or matrix.load_json('suites.json')['default'])
    if args.full and 'full' not in suites:
        suites.append('full')
    base = plugin.fresh_defaults(args.plugin)
    cases = matrix.cases(args.plugin, base, agents, suites, repeat=args.repeat, scenario_ids=args.scenario or (),
                         config_match=args.config or (), limit=args.limit)
    return agents, suites, cases


def print_plan(cases, suites, args):
    prices = cost.pricing()
    measured = cost.calibrate(args.calibrate) if args.calibrate else None
    rows = cost.estimate(cases, prices, measured, jobs=args.jobs)
    pairs = {(case['scenario']['id'], matrix.slug(case['config'])) for case in cases}
    print(f'Suites: {", ".join(suites)}')
    print(f'{len(pairs)} scenario and configuration pairs, x{args.repeat} repeat, {len(cases)} sessions in all.')
    print()
    header = f'{"Agent":<28} {"Sessions":>8} {"Turns":>6} {"Input":>9} {"Cache wr":>9} {"Cache rd":>9} ' \
             f'{"Output":>8} {"USD":>9} {"Hours":>6}  Tokens from'
    print(header)
    for row in rows:
        tokens = row['tokens']
        usd = 'no rate' if row['usd'] is None else f'${row["usd"]:.2f}'
        print(f'{row["agent"]["label"]:<28} {row["sessions"]:>8} {row["turns"]:>6} {millions(tokens["input"]):>9} '
              f'{millions(tokens["cache_write"]):>9} {millions(tokens["cache_read"]):>9} '
              f'{millions(tokens["output"]):>8} {usd:>9} {row["hours"]:>6.1f}  {row["profile"]}')
    print()
    print(f'Hours assume {args.jobs} sessions at a time. Prices: data/pricing.json. ' +
          (f'Tokens per turn measured in {args.calibrate}.' if measured else
           'Tokens per turn are the defaults in data/pricing.json; pass --calibrate RUN_DIR to use a measured run.'))
    print('Codex under a ChatGPT sign-in draws on plan limits; its dollar figure is the API price of the same tokens.')
    if any(row['usd'] is None for row in rows):
        print('A model with no rate in data/pricing.json has no dollar estimate.')
    return rows


def millions(count):
    return f'{count / 1_000_000:.2f}M'


def command_render(args):
    import render
    out = Path(args.out) if args.out else new_out_dir('render')
    rows = render.render_all(args.plugin, out, args.jobs)
    print(f'{len(rows)} policies rendered. Report: {out / "report.md"}')


def command_plan(args):
    agents, suites, cases = selection(args)
    print_plan(cases, suites, args)
    if args.list:
        print()
        for case in cases:
            print(f'{case["key"]}  ({", ".join(case["suites"])})')


def command_run(args):
    import runner
    agents, suites, cases = selection(args)
    rows = print_plan(cases, suites, args)
    if args.max_usd is not None:
        print(f'The run stops starting new sessions once it has spent ${args.max_usd:.2f}.')
    if not args.yes:
        if not sys.stdin.isatty():
            sys.exit('Pass --yes to start without a prompt.')
        if input(f'Start {len(cases)} sessions? [y/N] ').strip().lower() not in ('y', 'yes'):
            sys.exit('Nothing started.')
    out = Path(args.out) if args.out else new_out_dir('run')
    settings = {'suites': suites, 'repeat': args.repeat, 'full': args.full, 'scenario': args.scenario,
                'config': args.config, 'limit': args.limit, 'jobs': args.jobs, 'turn_timeout': args.turn_timeout,
                'max_usd': args.max_usd}
    run = runner.Run(out, args.work, args.plugin, agents, settings)
    run.write_manifest({'estimate': [{key: row[key] for key in ('agent', 'sessions', 'turns', 'tokens', 'usd')}
                                     for row in rows], 'cases': len(cases)})
    try:
        run.execute(cases, args.jobs, args.max_usd)
    finally:
        run.finish({})
    print(f'Spent ${run.spent:.4f} where measured. Summary: {out / "summary.md"}')
    if run.failures:
        print(f'{len(run.failures)} sessions failed to start; see failures in {out / "run.json"}.')


def command_report(args):
    variants, rows = report.write_index(args.run_dir)
    print(f'{variants} variants, {rows} turn rows. Summary: {Path(args.run_dir) / "summary.md"}')


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    result.add_argument('--plugin', type=Path, default=DEFAULT_PLUGIN,
                        help=f'the dialogue plugin to test (default: {DEFAULT_PLUGIN})')
    sub = result.add_subparsers(dest='command', required=True)

    render = sub.add_parser('render', help='render every configuration, without a model')
    render.add_argument('--out', help='output directory (default: a new directory under out/)')
    render.add_argument('--jobs', type=int, default=8)

    for name in ('plan', 'run'):
        command = sub.add_parser(name, help='estimate a run' if name == 'plan' else 'execute a run')
        command.add_argument('--agent', action='append', metavar='CLIENT:MODEL[:EFFORT]',
                             help=f'claude:MODEL or codex:MODEL, repeatable (default: {" ".join(DEFAULT_AGENTS)})')
        command.add_argument('--suite', action='append', help='a suite from data/suites.json, repeatable')
        command.add_argument('--full', action='store_true', help='add every combination of the five settings')
        command.add_argument('--scenario', action='append', help='only this scenario ID, repeatable')
        command.add_argument('--config', action='append', metavar='TEXT',
                             help='only configurations whose name contains TEXT, repeatable')
        command.add_argument('--repeat', type=int, default=1, help='sessions per case')
        command.add_argument('--limit', type=int, help='only the first N scenario and configuration pairs')
        command.add_argument('--jobs', type=int, default=4, help='sessions at a time')
        command.add_argument('--calibrate', metavar='RUN_DIR', help='estimate from the tokens measured in a run')
        if name == 'plan':
            command.add_argument('--list', action='store_true', help='print every case')
        else:
            command.add_argument('--out', help='output directory; an existing one keeps its complete variants')
            command.add_argument('--work', type=Path, default=DEFAULT_WORK,
                                 help=f'scratch space for workspaces and the Codex home (default: {DEFAULT_WORK})')
            command.add_argument('--yes', action='store_true', help='start without asking')
            command.add_argument('--max-usd', type=float, help='stop starting sessions after spending this much')
            command.add_argument('--turn-timeout', type=int, default=600, help='seconds for one turn')

    rebuild = sub.add_parser('report', help='rebuild transcripts, metrics, index.csv and summary.md')
    rebuild.add_argument('run_dir', type=Path)
    return result


def main():
    args = parser().parse_args()
    args.plugin = args.plugin.resolve()
    {'render': command_render, 'plan': command_plan, 'run': command_run, 'report': command_report}[args.command](args)


if __name__ == '__main__':
    main()
