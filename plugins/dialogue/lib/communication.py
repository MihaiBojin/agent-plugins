"""Communication guideline catalog and profile rendering."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "skills" / "dialogue"


def catalog():
    guidelines = json.loads((ROOT / "guidelines.json").read_text(encoding="utf-8"))
    profiles = json.loads((ROOT / "profiles.json").read_text(encoding="utf-8"))
    ids = [entry["id"] for entry in guidelines]
    types = ("structure", "brevity", "precision", "evidence", "risk", "language", "procedures")
    if any(entry.get("type") not in types for entry in guidelines):
        raise ValueError("invalid guideline type")
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


def effective_guidelines(profile, overrides=None):
    guidelines, profiles = catalog()
    selected = set(profiles[profile]["guidelines"])
    for key, value in (overrides or {}).items():
        if value:
            selected.add(key)
        else:
            selected.discard(key)
    return [entry for entry in guidelines if entry["id"] in selected]


def list_guidelines(profile, overrides=None, all_guidelines=False, group=None):
    guidelines, profiles = catalog()
    overrides = overrides or {}
    enabled = {e["id"] for e in effective_guidelines(profile, overrides)}
    lines = [f'Guidelines for {profile} ({len(enabled)}/{len(guidelines)} enabled):']
    for kind in ("structure", "brevity", "precision", "evidence", "risk", "language", "procedures"):
        if group and group != kind:
            continue
        entries = [e for e in guidelines if e["type"] == kind and (all_guidelines or e["id"] in enabled)]
        if not entries:
            continue
        lines.append(kind.title() + ":")
        for entry in entries:
            ident = entry["id"]
            status = "on" if ident in enabled else "off"
            source = "override" if ident in overrides else "profile"
            lines.append(f'- {ident} [{status}, {source}]: {entry["name"]} — {entry["description"]}')
    if not enabled and not all_guidelines:
        lines.append("(none)")
    return "\n".join(lines)


def render_profile(profile, overrides=None):
    guidelines, profiles = catalog()
    selected = profiles[profile]
    entries = effective_guidelines(profile, overrides)
    if profile in ("plain", "custom") and not entries:
        return ("Communication profile is plain: stop applying earlier dialogue "
                "communication-profile instructions. Use client and user instructions.")
    lines = [f"## Communication profile: {profile}"]
    if selected["instruction"]:
        lines.append(selected["instruction"])
    for entry in entries:
        lines.append(f'- {entry["name"]}: {entry["description"]}')
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


def workflows():
    return json.loads((ROOT / "workflows.json").read_text(encoding="utf-8"))


def wizard_questions(current=None):
    """Three choices, each showing names and short meanings."""
    current = current or {}
    _, profiles = catalog()
    languages = language_standards()
    modes = workflows()
    lines = [
        "Dialogue setup: answer three questions. Nothing changes until all answers are applied.",
        "1. Comms — how concise should responses be?"]
    for key, item in profiles.items():
        lines.append(f'   - {key}: {item["description"]}')
    lines.append("2. Style — how should technical English be written?")
    for key, item in languages.items():
        lines.append(f'   - {"ste" if key == "ste-inspired" else key}: {item["description"]}')
    lines.append("3. Workflow — how should structured messages and acknowledgments work?")
    for key, item in modes.items():
        lines.append(f'   - {key}: {item["description"]}')
    if current:
        lines.extend([
            "Current: comms={communication_profile}, style={language_standard}, "
            "situation={situation}, signals={signaling}".format(**current),
            "Select all three. Session stays enabled/disabled as it was."
        ])
    lines.append("Apply: setup apply --comms VALUE --style VALUE --workflow VALUE")
    lines.append("For finer control use set situation NAME and set signals off|intent|full.")
    return "\n".join(lines)


def full_help():
    _, profiles = catalog()
    languages = language_standards()
    modes = workflows()
    lines = [
        "# Dialogue help",
        "Start: help (this overview), setup (guided three-question configuration), enable/disable.",
        "Inspect: settings, profiles, guidelines, situations, languages, signals, state, render.",
        "Change: set comms VALUE | set style VALUE | set situation VALUE | set signals VALUE.",
        "Apply wizard: setup apply --comms VALUE --style VALUE --workflow VALUE.",
        "Defaults: defaults show | defaults set KEY VALUE (future sessions only).",
        "Legacy: set communication_profile, language_standard, signaling, response_style; situation use/preview/clear.",
        "",
        "Comms profiles:"]
    for key, item in profiles.items():
        lines.append(f'- {key}: {item["description"]}')
    lines.append("Language styles:")
    for key, item in languages.items():
        lines.append(f'- {"ste" if key == "ste-inspired" else key}: {item["description"]}')
    lines.append("Situational frameworks: none, auto, " + ", ".join(situations()))
    for key, item in situations().items():
        lines.append(f'- {key}: {item["description"]}')
    lines.append("Signals: off (none), intent (sender-intent labels), full (intent and response-status labels).")
    lines.append("Workflow presets for setup:")
    for key, item in modes.items():
        lines.append(f'- {key}: {item["description"]}')
    lines.append("Other settings: threads on/off, focus on/off, compact on/off, enabled on/off.")
    lines.append("Guidelines: guidelines (enabled by type), guidelines --all (include disabled), guidelines --group TYPE.")
    lines.append("Override: guideline on|off|reset ID; guideline reset all; guideline group on|off|reset TYPE.")
    lines.append("Group types: structure, brevity, precision, evidence, risk, language, procedures.")
    lines.append("Help/setup/preview do not enable Dialogue or write state.")
    return "\n".join(lines)
