# Error message

Reader: the person who hit the error, developer or end user, at the moment it
happened. They arrive asking what went wrong and how to fix it.

## Shape

An error message has five parts:

1. The specific cause, with the offending value and the violated constraint.
2. The fix, in the imperative. Several fixes go in a list.
3. An example of valid input.
4. A link, when the explanation runs past three sentences.
5. A stable error code or identifier.

Example: "Cannot write to /var/lib/app/cache: the directory is read-only. Run
the service as a user with write access, or set cache_dir to a writable path.
Error APP-0042."

## Rules

The message itself follows seven rules:

- Be concise, but never cryptic.
- Use no double negatives and no exceptions to exceptions.
- The same problem produces the same message everywhere, in the same terms
  (`terminology`).
- Say how to get it right, not what the user did wrong. Do not blame,
  apologize or joke (`no_filler`).
- Match the vocabulary to the reader: a shopper does not need to hear about
  server CPU load.
- Put the message next to the location of the error.
- Never rely on color alone. In a terminal, a color comes with a word such as
  FAIL or WARN (`not_by_sight`).

The code behind the message follows three:

- Do not fail silently, and do not swallow the root cause.
- Raise the error as early as it is useful.
- Log and document every error code.

Sources: Google Writing Helpful Error Messages, all 16 pages.
