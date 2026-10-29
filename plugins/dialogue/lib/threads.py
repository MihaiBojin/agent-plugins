"""Thread IDs and transitions. Closed IDs and spent letters remain recorded."""

import re


def order(identifier):
    return tuple(int(part) for part in identifier.split('.'))


def validate_threads(data):
    records = data.get('threads')
    if not isinstance(records, dict):
        raise ValueError('invalid thread records; state was not reset')
    siblings = {}
    for identifier, item in records.items():
        if not re.fullmatch(r'[1-9][0-9]*(?:\.[1-9][0-9]*)*', identifier):
            raise ValueError('invalid thread ID')
        if not isinstance(item, dict) or item.get('status') not in ('open', 'closed'):
            raise ValueError('invalid thread status')
        for field in ('title', 'body', 'context'):
            if not isinstance(item.get(field), str):
                raise ValueError(f'invalid thread {field}')
        if not isinstance(item.get('options'), dict):
            raise ValueError('invalid thread options')
        if list(item['options']) != [label(index) for index in range(1, len(item['options']) + 1)]:
            raise ValueError('invalid option sequence; state was not reset')
        for key, option in item['options'].items():
            if not re.fullmatch('[a-z]+', key) or not isinstance(option, dict):
                raise ValueError('invalid option')
            if option.get('status') not in ('live', 'chosen', 'rejected', 'closed') or not isinstance(option.get('text'), str):
                raise ValueError('invalid option state')
        parent = identifier.rpartition('.')[0]
        siblings.setdefault(parent, []).append(int(identifier.rsplit('.', 1)[-1]))
        if parent and (parent not in records or (item['status'] == 'open' and records[parent]['status'] != 'open')):
            raise ValueError('invalid parent thread state')
    for numbers in siblings.values():
        if sorted(numbers) != list(range(1, len(numbers) + 1)):
            raise ValueError('invalid thread sequence; state was not reset')
    active = data.get('active')
    if active is not None and (not isinstance(active, str) or active not in records or records[active]['status'] != 'open'):
        raise ValueError('invalid active thread')


def record(data, identifier):
    try:
        return data['threads'][identifier]
    except KeyError as error:
        raise ValueError(f'unknown thread: {identifier}') from error


def open_ids(data):
    return sorted((k for k, v in data['threads'].items() if v['status'] == 'open'), key=order)


def select_active(data):
    if data['active'] not in open_ids(data):
        data['active'] = next(iter(open_ids(data)), None)


def label(index):
    result = ''
    while index:
        index, remainder = divmod(index - 1, 26)
        result = chr(97 + remainder) + result
    return result


def add(data, title, body='', context='', parent=None):
    if not title.strip() or '\n' in title:
        raise ValueError('thread title must be a nonempty single line')
    if '\n' in context:
        raise ValueError('context must be a single line')
    if parent and record(data, parent)['status'] != 'open':
        raise ValueError('parent must be open')
    prefix = parent + '.' if parent else ''
    number = 1
    while prefix + str(number) in data['threads']:
        number += 1
    identifier = prefix + str(number)
    data['threads'][identifier] = {'title': title, 'body': body, 'context': context, 'status': 'open', 'options': {}}
    select_active(data)
    return show(data, identifier)


def close(data, identifier):
    record(data, identifier)
    changed = []
    for key in sorted(data['threads'], key=order):
        if key == identifier or key.startswith(identifier + '.'):
            item = data['threads'][key]
            if item['status'] == 'open':
                changed.append(key + '/')
            item['status'] = 'closed'
            for option in item['options'].values():
                if option['status'] == 'live':
                    option['status'] = 'closed'
    select_active(data)
    return 'Closed: ' + ', '.join(changed) if changed else 'Thread already closed.'


def reopen(data, identifier):
    record(data, identifier)
    parts = identifier.split('.')
    for size in range(1, len(parts) + 1):
        record(data, '.'.join(parts[:size]))['status'] = 'open'
    select_active(data)
    return show(data, identifier)


def show(data, identifier, details=True):
    item = record(data, identifier)
    lines = ['---', '', f'## {identifier}/ {item["title"]}']
    if details:
        if item['context']:
            lines.extend(['', 'Context: ' + item['context']])
        if item['body']:
            lines.extend(['', item['body']])
        options = [f'{identifier}{key}/ {value["text"]}' for key, value in item['options'].items() if value['status'] == 'live']
        if options:
            lines.extend(['', *options])
    return '\n'.join(lines)


def listing(data, details=False, identifiers=None):
    ids = open_ids(data) if identifiers is None else identifiers
    return '\n\n'.join(show(data, identifier, details) for identifier in ids) or 'No open threads.'


def footer(data, shown):
    unknown = set(shown) - set(data['threads'])
    if unknown:
        raise ValueError('unknown shown thread: ' + ', '.join(sorted(unknown)))
    count = len(set(open_ids(data)) - set(shown))
    if not count:
        return ''
    noun = 'thread' if count == 1 else 'threads'
    return f'{count} other open {noun}. Type `=/` for headings or `=//` for details.'


def mutate(data, args):
    if not data['settings']['enabled'] or not data['settings']['threads']:
        raise ValueError('thread tracking is disabled; enable dialogue and threads explicitly')
    op = args.operation
    if op == 'open':
        return add(data, args.title, args.body, args.context, args.parent)
    item = record(data, args.id)
    if op == 'close':
        return close(data, args.id)
    if op == 'reopen':
        return reopen(data, args.id)
    if op == 'focus':
        if item['status'] != 'open':
            raise ValueError('cannot focus a closed thread')
        data['active'] = args.id
        return show(data, args.id)
    if op == 'update':
        previous = item['title']
        if args.title is not None:
            if not args.title.strip() or '\n' in args.title:
                raise ValueError('thread title must be a nonempty single line')
            item['title'] = args.title
        if args.body is not None:
            item['body'] = args.body
        if args.context is not None:
            if '\n' in args.context:
                raise ValueError('context must be a single line')
            item['context'] = args.context
        output = show(data, args.id)
        if item['title'] != previous:
            heading = f'## {args.id}/ {item["title"]}'
            output = output.replace(heading, heading + f'\nReplaces: {args.id}/ {previous}', 1)
        return output
    if item['status'] != 'open':
        raise ValueError('thread must be open')
    if op == 'option':
        if not args.text.strip() or '\n' in args.text:
            raise ValueError('option text must be a nonempty single line')
        letter = label(len(item['options']) + 1)
        item['options'][letter] = {'text': args.text, 'status': 'live'}
        return show(data, args.id)
    option = item['options'].get(args.letter)
    if not option or option['status'] != 'live':
        raise ValueError('option is not live')
    option['status'] = 'chosen' if op == 'choose' else 'rejected'
    return close(data, args.id) if op == 'choose' else show(data, args.id)
