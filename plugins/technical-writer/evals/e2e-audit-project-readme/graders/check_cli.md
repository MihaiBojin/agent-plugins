---
type: regex
target: trace
pattern: '(?:^|\n)(?![^\n]*"is_error"\s*:\s*true)(?=[^\n]*(?:"type"\s*:\s*"tool_result"|"exit_code"\s*:\s*0\b))[^\n]*"(?:content|aggregated_output)"\s*:\s*"(?:(?:[^"\\]|\\.)*?\\n)?(?:Usage: sh pin-count\.sh --manifest FILE\\nCount the package pins in FILE\.|2)(?:\\n|")'
---

Running the help command shows the supported flag. The corrected quickstart
also verifies the CLI and prints the two pins in the manifest.
