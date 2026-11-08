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
            lines.append(f'- {entry["name"]} ({entry["id"]}): {entry["description"]}')
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


def situations():
    return json.loads((ROOT / "situations.json").read_text(encoding="utf-8"))


def language_standards():
    return json.loads((ROOT / "language.json").read_text(encoding="utf-8"))


def signals():
    return json.loads((ROOT / "signals.json").read_text(encoding="utf-8"))


def list_situations():
    lines = ["| Situation | Purpose |", "| --- | --- |"]
    for name, item in situations().items():
        lines.append(f'| {name} | {item["description"]} |')
    return "\n".join(lines)


def render_situation(name):
    if name == "none":
        return "No situational framework selected."
    items = situations()
    if name == "auto":
        lines = ["Situational mode: auto. Apply ONE framework when the user explicitly requests that type of communication or the task clearly demands it. Do not force a framework onto ordinary replies or coding tasks."]
        for key, item in items.items():
            lines.append(f'- {key}: {item["description"]} Use for {", ".join(item["uses"])}.')
        lines.append("Preserve safety-critical qualifications. Never omit necessary fields merely to reduce tokens.")
        return "\n".join(lines)
    if name not in items:
        raise ValueError("unknown situation: " + name)
    item = items[name]
    lines = [f'## Situational framework: {name}', item["description"]]
    for title, meaning in item["fields"]:
        lines.append(f'- {title}: {meaning}')
    lines.append(item["guidance"])
    lines.append("Use the framework only where relevant; do not invent missing details. Ask only for essential unknowns.")
    return "\n".join(lines)


def render_language(name):
    catalog = language_standards()
    if name not in catalog:
        raise ValueError("unknown language standard: " + name)
    if name == "plain":
        return ""
    return f'## Language standard: {name}\n{catalog[name]["instruction"]}'


def list_language():
    lines = ["| Standard | Description |", "| --- | --- |"]
    for key, item in language_standards().items():
        lines.append(f'| {key} | {item["description"]} |')
    return "\n".join(lines)


def render_signals(mode):
    if mode == "off":
        return ""
    catalog = signals()
    lines = ["## Communication signals",
             "Use intent markers only when they disambiguate a request, decision, warning, or update. Do not prepend a marker to every message."]
    for item in catalog["intents"]:
        lines.append(f'- {item["id"]}: {item["meaning"]}')
    if mode == "full":
        lines.append("When a reply needs a response status, use these meanings precisely. Acknowledgment is not acceptance; acceptance is not completion.")
        for item in catalog["responses"]:
            lines.append(f'- {item["id"]}: {item["meaning"]}')
    return "\n".join(lines)


def list_signals():
    catalog = signals()
    lines = ["Intent markers:"]
    lines += [f'- {x["id"]}: {x["meaning"]}' for x in catalog["intents"]]
    lines += ["Response markers:"]
    lines += [f'- {x["id"]}: {x["meaning"]}' for x in catalog["responses"]]
    return "\n".join(lines)
