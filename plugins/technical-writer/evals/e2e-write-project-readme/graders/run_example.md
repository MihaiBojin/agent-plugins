---
type: regex
target: trace
pattern: '(?:^|\n)(?![^\n]*"is_error"\s*:\s*true)(?=[^\n]*(?:"type"\s*:\s*"tool_result"|"exit_code"\s*:\s*0\b))[^\n]*"(?:content|aggregated_output)"\s*:\s*"(?:(?:[^"\\]|\\.)*?\\n)?WARN=2(?:\\n|")'
---

The example produced the expected output in a tool result.
