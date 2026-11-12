# The sentence-level rules

Restated from Google's [Technical Writing One](https://developers.google.com/tech-writing/one)
and [Technical Writing Two](https://developers.google.com/tech-writing/two).
Both are Creative Commons Attribution 4.0; the wording here is ours and the
rules are theirs, so follow a link when a rule needs its examples.

A repository with writing rules of its own outranks all of this. Read
`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md` and any style guide first, and
apply them where they disagree with what follows.

Each rule under a `###` heading opens with the ID and the first line that the
dialogue and technical-writing plugins give it, so all three plugins state it
the same way.

## Before the first sentence

### `sufficient`

Include only what the reader needs to understand, decide, act, or verify.

[Say who it is for and what it covers](https://developers.google.com/tech-writing/one/documents).
Name the audience and what that audience already knows. State the scope, and
state what is out of scope when a reader could reasonably expect it.

### `bluf`

Lead with the answer, result, decision, or blocker.

Put the key points at the start rather than building to them.

## Sentences

### `direct`

Use active voice, precise nouns, and concrete verbs. Name the actor, or say it is unknown.

[Active voice](https://developers.google.com/tech-writing/one/active-voice) is
actor, then verb, then target. Passive voice reverses that or drops the actor
altogether. To spot it, look for a form of `be` followed by a past participle,
often with a preposition after the verb: "the file is read by the parser".
An imperative verb opening a sentence is active, not passive, however much it
looks like one.

### `short_sentences`

One idea per sentence. Aim for 20 words in an instruction and 25 in a description; an identifier, number or quoted string counts as one word.

[One sentence, one idea](https://developers.google.com/tech-writing/one/short-sentences).
When editing, look hard at every subordinate clause and ask whether it extends
the idea or starts a second one. A long sentence joined by "or" is usually a
bulleted list that has not been written yet, and so is a list of items buried
inside a sentence.

### `no_filler`

Remove praise, pleasantries, repetition, and needless adjectives or superlatives.

Cut filler. Google's own examples: "at this point in time" is "now",
"determine the location of" is "find", "is able to" is "can".

## Words

### `define_terms`

Define or link a term the reader may not know; spell out an acronym on first use.

[Define a term once, then use it](https://developers.google.com/tech-writing/one/words).
An acronym earns its expansion in parentheses on first use only when it comes
back later; one that appears once should have stayed spelled out.

### `terminology`

One name per concept and one sentence pattern per repeated step. Introduce a short form once and then use only it. Quote identifiers exactly.

Use each term the same way every time. Two names for one thing read as two
things.

### `pronouns`

Replace a pronoun with its noun when the referent is not the nearest noun, and follow "this" with the noun it means.

Keep a pronoun near its noun. Google's threshold is five words: when more than
five separate them, repeat the noun instead. `it`, `this`, `that` and `they`
after a paragraph of nouns point at whatever the reader last thought about.

## Lists and tables

### `scannable`

Introduce a list with a sentence ending in a colon. Number ordered steps, bullet the rest, and keep items parallel and one level deep.

[Bulleted for unordered, numbered for ordered](https://developers.google.com/tech-writing/one/lists-and-tables).
Keep the items parallel in four respects: grammar, logical category,
capitalisation and punctuation. Start each step of a numbered list with an
imperative verb. Introduce a list or a table with a sentence that ends in a
colon, so the reader knows what they are about to look at.

### `tables`

Use a table when two or more things are compared.

A table earns its place when the data has two dimensions. One column is a list.

## Editing

[Technical Writing Two's editing unit](https://developers.google.com/tech-writing/two/editing)
gives five moves, and the first one costs nothing:

1. Read it aloud. Awkward phrasing and overlong sentences are audible before
   they are visible.
2. Read it as the audience, not as the person who wrote the code.
3. Leave it and come back. Fresh eyes find what tired ones wrote.
4. Change the context: another font, another medium, print.
5. Cut what the reader does not need, including sentences that were expensive
   to write.
