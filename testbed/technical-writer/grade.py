"""Grade a document against every rule of the skill, with a judge model that sees the rules, the task and the document.

The judge always gets the full skill's rules, whatever the configuration removed, so a rule's pass rate in a
configuration without it says what the writer does when nobody told it the rule.
"""

import json
import re

SYSTEM = ('You grade a technical document against writing rules. For each rule, answer "pass" when the document '
          'follows it, "na" when the rule cannot apply to this document, and "fail: " followed by the reason, at '
          'most 20 words that quote the passage, when any part of the document breaks it. Judge only what the '
          'document shows. Reply with only a JSON object that maps each rule ID to its answer.')
VERDICTS = {'pass': 1.0, 'fail': 0.0}


def prompt(task, rules, document):
    listed = '\n\n'.join(f'### `{rule["id"]}`\n{rule["text"]}' for rule in rules)
    return (f'The writer was given this task:\n\n<task>\n{task}\n</task>\n\nThe rules:\n\n{listed}\n\n'
            f'The document:\n\n<document>\n{document}\n</document>\n\n'
            f'Answer for each of these IDs: {", ".join(rule["id"] for rule in rules)}.')


def answer(value):
    """pass, fail or na, from a judge's answer such as "fail: the step joins two commands"."""
    word = str(value).strip().lower().split(':')[0].strip()
    return word if word in ('pass', 'fail', 'na') else None


def parse(text, ids):
    """Rule ID to 1.0 for pass and 0.0 for fail; a rule the judge marked na, or left out, has no value."""
    match = re.search(r'\{.*\}', text or '', re.DOTALL)
    if not match:
        return None
    try:
        verdicts = json.loads(match.group(0))
    except ValueError:
        return None
    if not isinstance(verdicts, dict):
        return None
    return {identifier: VERDICTS[answer(verdicts[identifier])] for identifier in ids
            if identifier in verdicts and answer(verdicts[identifier]) in VERDICTS}


def reasons(text):
    """Rule ID to the judge's reason, for each rule it failed."""
    match = re.search(r'\{.*\}', text or '', re.DOTALL)
    try:
        verdicts = json.loads(match.group(0)) if match else {}
    except ValueError:
        return {}
    return {identifier: str(value).split(':', 1)[1].strip() for identifier, value in verdicts.items()
            if answer(value) == 'fail' and ':' in str(value)} if isinstance(verdicts, dict) else {}
