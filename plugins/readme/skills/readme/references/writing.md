# The sentence-level rules

Restated from Google's [Technical Writing One](https://developers.google.com/tech-writing/one)
and [Technical Writing Two](https://developers.google.com/tech-writing/two).
Both are Creative Commons Attribution 4.0; the wording here is ours and the
rules are theirs, so follow a link when a rule needs its examples.

A repository with writing rules of its own outranks all of this. Read
`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md` and any style guide first, and
apply them where they disagree with what follows.

## Before the first sentence

[Say who it is for and what it covers](https://developers.google.com/tech-writing/one/documents).
Name the audience and what that audience already knows. State the scope, and
state what is out of scope when a reader could reasonably expect it. Put the
key points at the start rather than building to them.

## Sentences

[Active voice](https://developers.google.com/tech-writing/one/active-voice) is
actor, then verb, then target. Passive voice reverses that or drops the actor
altogether. To spot it, look for a form of `be` followed by a past participle,
often with a preposition after the verb: "the file is read by the parser".
An imperative verb opening a sentence is active, not passive, however much it
looks like one.

[One sentence, one idea](https://developers.google.com/tech-writing/one/short-sentences).
When editing, look hard at every subordinate clause and ask whether it extends
the idea or starts a second one. A long sentence joined by "or" is usually a
bulleted list that has not been written yet, and so is a list of items buried
inside a sentence.

Cut filler. Google's own examples: "at this point in time" is "now",
"determine the location of" is "find", "is able to" is "can".

## Words

[Define a term once, then use it](https://developers.google.com/tech-writing/one/words),
the same way every time. Two names for one thing read as two things. An acronym
earns its expansion in parentheses on first use only when it comes back later;
one that appears once should have stayed spelled out.

Keep a pronoun near its noun. Google's threshold is five words: when more than
five separate them, repeat the noun instead. `it`, `this`, `that` and `they`
after a paragraph of nouns point at whatever the reader last thought about.

## Lists and tables

[Bulleted for unordered, numbered for ordered](https://developers.google.com/tech-writing/one/lists-and-tables).
Keep the items parallel in four respects: grammar, logical category,
capitalisation and punctuation. Start each step of a numbered list with an
imperative verb. Introduce a list or a table with a sentence that ends in a
colon, so the reader knows what they are about to look at.

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
