"""Countable features of one reply and one turn, the same set for every scenario."""

import re

from clients import command_of, dialogue_op, narration

CONTRACTION = re.compile(r"\b\w+(?:n't|'s|'re|'ve|'ll|'d|'m)\b", re.IGNORECASE)
SENTENCE_END = re.compile(r'(?<=[.!?])\s+')
LATIN = re.compile(r'(?<![\w.])(?:e\.g\.|i\.e\.|etc\.|vs\.|cf\.|viz\.|et al\.)', re.IGNORECASE)
ACRONYM = re.compile(r'(?<![\w`/-])([A-Z][A-Z0-9]{1,5})s?(?![\w`/-])')
# Signal and response markers are the protocol's own words, not acronyms to define.
NOT_ACRONYMS = {'FYI', 'REQUEST', 'DECISION', 'DECISIONS', 'PROPOSAL', 'CAUTION', 'WARNING', 'QUESTION', 'UPDATE',
                'ACK', 'ACCEPTED', 'NEED', 'INFO', 'BLOCKED', 'DONE', 'CANCELLED', 'OK'}
DEMONSTRATIVE = re.compile(r'\b(?:[Tt]his|[Tt]hese|[Tt]hose|That)\s+(?:is|was|are|were|means|meant|will|would|can|could|'
                           r'should|does|did|has|had|keeps|lets|makes|breaks|fixes|works|happens|matters|leaves)\b')
LIST_ITEM = re.compile(r'^\s*(?:[-*+]|\d+[.)])\s')
NESTED_ITEM = re.compile(r'^(?:\s{2,}|\t)(?:[-*+]|\d+[.)])\s')
FENCED = re.compile(r'```.*?```', re.DOTALL)


def sentences(text):
    """Prose sentences: code blocks, tables and headings removed."""
    prose = re.sub(r'```.*?```', ' ', text, flags=re.DOTALL)
    lines = [line for line in prose.splitlines()
             if line.strip() and not line.lstrip().startswith(('|', '#', '---'))]
    joined = ' '.join(re.sub(r'^\s*(?:[-*+]|\d+[.)])\s+', '', line) for line in lines)
    return [part for part in SENTENCE_END.split(joined) if re.search(r'\w', part)]


def prose(text):
    """The reply without fenced code or inline code spans."""
    return re.sub(r'`[^`\n]*`', ' ', FENCED.sub(' ', text))


def unexpanded_acronyms(text):
    """Distinct acronyms whose first use has no parenthesis beside it, as in `time to live (TTL)` or `TTL (time to live)`."""
    text = prose(text)
    seen, count = set(), 0
    for match in ACRONYM.finditer(text):
        word = match.group(1)
        if word in seen or word in NOT_ACRONYMS:
            continue
        seen.add(word)
        count += not (text[:match.start()].rstrip()[-1:] == '(' or text[match.end():].lstrip()[:1] == '(')
    return count


def long_paragraphs(text):
    """Prose paragraphs of more than six sentences."""
    blocks = [block.splitlines() for block in re.split(r'\n\s*\n', FENCED.sub('', text)) if block.strip()]
    return sum(len(sentences(' '.join(lines))) > 6 for lines in blocks
               if not any(LIST_ITEM.match(line) or line.lstrip().startswith(('|', '#')) for line in lines))


def lists_without_lead_in(text):
    """Top-level lists whose line above does not end with a colon."""
    count, previous = 0, ''
    for line in FENCED.sub('', text).splitlines():
        if LIST_ITEM.match(line) and not NESTED_ITEM.match(line) and not LIST_ITEM.match(previous):
            count += not previous.rstrip().endswith(':')
        if line.strip():
            previous = line
    return count


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
        'latin_abbreviations': len(LATIN.findall(prose(text))),
        'unexpanded_acronyms': unexpanded_acronyms(text),
        'bare_demonstratives': len(DEMONSTRATIVE.findall(prose(text))),
        'long_paragraphs': long_paragraphs(text),
        'lists_without_lead_in': lists_without_lead_in(text),
        'nested_items': sum(bool(NESTED_ITEM.match(line)) for line in FENCED.sub('', text).splitlines()),
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
