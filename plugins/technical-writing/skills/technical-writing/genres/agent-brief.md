# Agent brief

Reader: an agent that knows only what the brief says. Google's unit on LLMs
treats prompting as technical writing, and its checklist gives the shape.

## Shape

A brief has seven parts:

1. A role.
2. The goal: what the reader of the output should know or do.
3. The audience and document type of the output.
4. The context, with each attachment marked as fact or draft. A model assumes
   that attachments are true, so it can describe bugs in attached code as
   features.
5. Constraints, such as "use only these sources".
6. What is already ruled out.
7. The format and length of the output.

Sources: TW2 Using LLMs.
