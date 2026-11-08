"""Communication guideline catalog and profile rendering."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "skills" / "dialogue"


def catalog():
    guidelines = json.loads((ROOT / "guidelines.json").read_text(encoding="utf-8"))
    profiles = json.loads((ROOT / "profiles.json").read_text(encoding="utf-8"))
    ids = [entry["id"] for entry in guidelines]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate guideline ID")
    if any(len(set(profile["guidelines"])) != len(profile["guidelines"])
           or not set(profile["guidelines"]).issubset(ids)
           for profile in profiles.values()):
        raise ValueError("invalid profile guideline references")
    return guidelines, profiles


def names():
    return tuple(catalog()[1])


def description(profile):
    return catalog()[1][profile]["description"]


def list_profiles(current):
    _, profiles = catalog()
    lines = ["| Profile | Active | Purpose | Guidelines |",
             "| --- | --- | --- | --- |"]
    for name, entry in profiles.items():
        lines.append(f'| {name} | {"yes" if current == name else ""} | {entry["description"]} | {len(entry["guidelines"])} |')
    return "\n".join(lines)


def list_guidelines(profile):
    guidelines, profiles = catalog()
    enabled = set(profiles[profile]["guidelines"])
    lines = [f'Enabled guidelines for profile {profile} ({len(enabled)}/{len(guidelines)}):']
    for entry in guidelines:
        if entry["id"] in enabled:
            lines.append(f'- {entry["id"]}: {entry["description"]}')
    if not enabled:
        lines.append("(none)")
    return "\n".join(lines)


def render_profile(profile):
    guidelines, profiles = catalog()
    selected = profiles[profile]
    lines = [f"## Communication profile: {profile}", selected["instruction"]]
    enabled = set(selected["guidelines"])
    for entry in guidelines:
        if entry["id"] in enabled:
            lines.append(f'- {entry["name"]}: {entry["description"]}')
    if profile == "plain":
        return ("Communication profile is plain: stop applying earlier dialogue "
                "communication-profile instructions. Use client and user instructions.")
    lines.extend(["",
                  "Use completion: Result → Verification → Remaining issues.",
                  "Use review: Findings by severity → Evidence → Suggested fix.",
                  "Use blocker: Blocker → Cause → Required action.",
                  "Use decision: Recommendation → Reason → Trade-off.",
                  "Use progress: Material change → Next action.",
                  "Omit empty sections. Honor specific user formatting requests.",
                  "Keep threads and their metadata under the separate thread protocol."])
    return "\n".join(lines)
