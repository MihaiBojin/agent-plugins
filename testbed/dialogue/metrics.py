"""Countable features of one reply and one turn, the same set for every scenario."""

import re

from clients import command_of, dialogue_op, narration

CONTRACTION = re.compile(r"\b\w+(?:n't|'s|'re|'ve|'ll|'d|'m)\b", re.IGNORECASE)
SENTENCE_END = re.compile(r'(?<=[.!?])\s+')


def sentences(text):
    """Prose sentences: code blocks, tables and headings removed."""
    prose = re.sub(r'```.*?```', ' ', text, flags=re.DOTALL)
    lines = [line for line in prose.splitlines()
             if line.strip() and not line.lstrip().startswith(('|', '#', '---'))]
    joined = ' '.join(re.sub(r'^\s*(?:[-*+]|\d+[.)])\s+', '', line) for line in lines)
    return [part for part in SENTENCE_END.split(joined) if re.search(r'\w', part)]


def field_present(text, field):
    """A framework field used as a label: a heading, bold text, a table cell, or 'Field:'."""
    name = re.escape(field)
    return re.search(rf'(?im)^(?:\s*#+\s*|\s*[-*]\s+|\s*\|\s*)?(?:\*\*)?{name}(?:\*\*)?\s*(?::|\||$|\*\*)', text) \
        is not None


def framework(text, frameworks):
    """The framework whose fields the reply uses most, as 'name 3/4', or ''."""
    best = ''
    best_share = 0.0
    for name, fields in frameworks.items():
        present = sum(field_present(text, field) for field in fields)
        share = present / len(fields)
        if present >= 2 and share > best_share:
            best, best_share = f'{name} {present}/{len(fields)}', share
    return best


def reply_metrics(text, terms):
    lines = text.splitlines()
    words = re.findall(r"[\w'’-]+", text)
    spans = [len(re.findall(r"[\w'’-]+", sentence)) for sentence in sentences(text)]
    markers = terms['intents'] + terms['responses']
    used = {marker: len(re.findall(rf'(?<![\w-]){re.escape(marker)}(?![\w-])', text)) for marker in markers}
    return {
        'words': len(words),
        'lines': len(lines),
        'sentences': len(spans),
        'mean_sentence_words': round(sum(spans) / len(spans), 1) if spans else 0,
        'long_sentences': sum(span > 25 for span in spans),
        'headings': sum(bool(re.match(r'\s*#{1,6}\s', line)) for line in lines),
        'bullets': sum(bool(re.match(r'\s*[-*+]\s', line)) for line in lines),
        'numbered_items': sum(bool(re.match(r'\s*\d+[.)]\s', line)) for line in lines),
        'tables': sum(bool(re.match(r'\s*\|?\s*:?-{3,}:?\s*\|', line)) for line in lines),
        'code_blocks': text.count('```') // 2,
        'em_dashes': text.count('—'),
        'contractions': len(CONTRACTION.findall(text)),
        'decisions_heading': '### DECISIONS' in text,
        'thread_headings': len(re.findall(r'(?m)^###\s+\d+/', text)),
        'option_lines': len(re.findall(r'(?m)^\s*\d+[a-z]+/\s', text)),
        'recommended': text.count('(recommended)'),
        'footer': bool(re.search(r'other open threads?\b', text)),
        'markers': ' '.join(f'{marker}x{count}' for marker, count in used.items() if count),
        'framework': framework(text, terms['frameworks']),
    }


def thread_counts(state):
    threads = (state or {}).get('threads') or {}
    return {
        'threads_open': sum(item['status'] == 'open' for item in threads.values()),
        'threads_closed': sum(item['status'] == 'closed' for item in threads.values()),
        'options': sum(len(item.get('options') or {}) for item in threads.values()),
    }


def turn_metrics(turn, terms):
    """Reply features, plus what the agent did with tools and what the saved state holds after the turn."""
    tools = [item for item in turn['items'] if item['type'] == 'tool']
    ops = [op for op in (dialogue_op(command) for command in map(command_of, tools) if command) if op]
    settings = ((turn.get('state_after') or {}).get('settings') or {})
    return {
        **reply_metrics(turn.get('reply') or '', terms),
        'narration_blocks': len(narration(turn['items'])),
        'tool_calls': len(tools),
        'failed_tool_calls': sum(item['is_error'] for item in tools),
        'dialogue_calls': len(ops),
        'dialogue_ops': ', '.join(ops),
        **thread_counts(turn.get('state_after')),
        'enabled_after': settings.get('enabled'),
        'comms_after': settings.get('communication_profile'),
        'situation_after': settings.get('situation'),
    }
