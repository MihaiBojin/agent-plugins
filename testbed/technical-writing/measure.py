"""How simple a document reads: its length, sentence and word lengths, readability, and the marks rules forbid."""

import re

from metrics import CONTRACTION, sentences

WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*")
PASSIVE = re.compile(r"\b(?:is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?\w+ed\b", re.IGNORECASE)


def syllables(word):
    """Vowel groups, less a silent final e: a count good enough to compare documents, not to hyphenate."""
    word = word.lower().strip("'’-")
    groups = re.findall(r'[aeiouy]+', word)
    count = len(groups) - (word.endswith('e') and not word.endswith(('le', 'ee')) and len(groups) > 1)
    return max(count, 1)


def prose(text):
    """The text without code blocks and inline code, whose words are not the writer's to choose."""
    return re.sub(r'`[^`\n]*`', ' ', re.sub(r'```.*?```', ' ', text, flags=re.DOTALL))


def measure(text):
    lines = text.splitlines()
    words = WORD.findall(prose(text))
    spans = [len(WORD.findall(sentence)) for sentence in sentences(prose(text))]
    counts = [syllables(word) for word in words]
    per_sentence = sum(spans) / len(spans) if spans else 0.0
    per_word = sum(counts) / len(counts) if counts else 0.0
    return {
        'words': len(words),
        'sentences': len(spans),
        'words_per_sentence': round(per_sentence, 2),
        'long_sentences': sum(span > 25 for span in spans),
        'chars_per_word': round(sum(len(word) for word in words) / len(words), 2) if words else 0.0,
        'long_words_pct': round(100 * sum(count >= 3 for count in counts) / len(counts), 1) if counts else 0.0,
        # Flesch-Kincaid grade level: the school grade a reader needs, from sentence and word length.
        'grade': round(0.39 * per_sentence + 11.8 * per_word - 15.59, 2) if words else 0.0,
        'passive': len(PASSIVE.findall(prose(text))),
        'em_dashes': text.count('—'),
        'contractions': len(CONTRACTION.findall(prose(text))),
        'headings': sum(bool(re.match(r'\s*#{1,6}\s', line)) for line in lines),
        'bullets': sum(bool(re.match(r'\s*[-*+]\s', line)) for line in lines),
        'numbered_items': sum(bool(re.match(r'\s*\d+[.)]\s', line)) for line in lines),
        'tables': sum(bool(re.match(r'\s*\|?\s*:?-{3,}:?\s*\|', line)) for line in lines),
    }
