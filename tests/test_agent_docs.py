#!/usr/bin/env python3
"""Structural checks for the agent contract, decision log, and README.

Reads the committed AGENTS.md, README.md, MEMORY.md, and DECISIONS.md.
Prints one `assert:` line per check so a saved run shows what was covered.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = {
    "AGENTS.md": ROOT / "AGENTS.md",
    "README.md": ROOT / "README.md",
    "MEMORY.md": ROOT / "MEMORY.md",
    "DECISIONS.md": ROOT / "DECISIONS.md",
}

# Phrases the starter still requires of this finished API.
STARTER_OBLIGATIONS = (
    "this repository is the workspace root",
    "query Postgres `v1_*` views only, never Ash tables",
    "ordinary JSON for the OpenAPI routes, not Ash JSON:API",
    "register once on boot and keep serving if the CMS is down (no heartbeat)",
    "does not touch the database",
    "GET /health",
)

# Facts the starter does not know, and stale notes must not replace.
COBOL_DELTAS = (
    "free-format GnuCOBOL (`-free`",
    "language COBOL and framework POSIX sockets",
    "Live SQL and listening go through the C trampolines (libpq and dual-stack listen), not embedded SQL and not a copy of another sibling's server",
    "Handler tests call the shipped router with a fake catalog",
    "Local gates are `make test`, `sast`, `audit`, `gitleaks`, and `lint`",
    "includes a `talks` array",
)

ADR_FIELDS = (
    "Status:",
    "Context:",
    "Alternatives considered:",
    "Decision:",
    "Consequences:",
)

ADR_TOPICS = {
    "ADR-0001": ("C trampoline", "embedded SQL", "socket"),
    "ADR-0002": ("free-format", "-free"),
    "ADR-0003": ("TSV", "libpq"),
    "ADR-0004": ("GnuCOBOL 3.2", "Bookworm", "gnucobol"),
    "ADR-0005": ("talks", "year-scoped"),
}

STALE_TREE = (
    "mongoose",
    "cJSON",
    "cjson",
    "4017",
    "carolina_api.cob",
    "CRaC",
    "crac",
)

# Assignment of a token-like name to a value other than the public starter example.
TOKEN_ASSIGN = re.compile(
    r"""(?ix)
    \b(?P<name>[A-Z0-9_]*(?:TOKEN|SECRET|API_KEY|PASSWORD)[A-Z0-9_]*)
    \s*=\s*
    (?P<value>`[^`]+`|"[^"]+"|'[^']+'|\S+)
    """
)
ALLOWED_TOKEN_VALUES = {
    "dev",
    "`dev`",
    '"dev"',
    "'dev'",
    "{POLYGLOT_REGISTER_TOKEN}",
    "`{POLYGLOT_REGISTER_TOKEN}`",
}
PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")
HOME_PATH = re.compile(r"/home/[A-Za-z0-9._-]+")
SECRET_PATH = re.compile(r"/run/secrets")
PRIVATE_HOST = re.compile(
    r"(?i)(?:zebra-hydra|\.ts\.net\b|\.internal\b)"
)
TOKEN_PREFIX = re.compile(
    r"(?:ghp_|gho_|github_pat_|glpat-|sk-|xox[baprs]-|AKIA[0-9A-Z]{16})"
)
FRAMEWORK_SEMVER = re.compile(
    r"POSIX sockets(?:\s+|[-/])v?\d+\.\d+",
    re.I,
)


def _say(label: str) -> None:
    print(f"assert: {label}")


class AgentDocTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = {}
        for name, path in DOCS.items():
            cls.text[name] = path.read_text(encoding="utf-8")

    def test_files_exist(self):
        for name, path in DOCS.items():
            self.assertTrue(path.is_file(), f"missing {name}")
            self.assertGreater(len(self.text[name].strip()), 0, f"empty {name}")
            _say(f"{name} exists and is non-empty")

    def test_starter_obligations(self):
        agents = self.text["AGENTS.md"]
        folded = agents.casefold()
        for phrase in STARTER_OBLIGATIONS:
            self.assertIn(
                phrase.casefold(),
                folded,
                f"AGENTS.md missing starter obligation: {phrase}",
            )
            _say(f"starter obligation present: {phrase}")
        self.assertIn("application/vnd.api+json", agents)
        _say("starter obligation present: ordinary JSON is not application/vnd.api+json")
        self.assertIn("workspace root", agents)
        _say("starter obligation present: workspace root")

    def test_cobol_deltas(self):
        agents = self.text["AGENTS.md"]
        for phrase in COBOL_DELTAS:
            self.assertIn(phrase, agents, f"AGENTS.md missing COBOL delta: {phrase}")
            _say(f"COBOL delta present: {phrase}")
        for stale in STALE_TREE:
            self.assertNotIn(stale, agents, f"AGENTS.md still describes stale tree fact: {stale}")
            _say(f"stale tree fact absent from AGENTS.md: {stale}")

    def test_agents_points_at_memory_files(self):
        agents = self.text["AGENTS.md"]
        self.assertIn("MEMORY.md", agents)
        self.assertIn("DECISIONS.md", agents)
        _say("AGENTS.md names MEMORY.md and DECISIONS.md")
        self.assertIn(
            "When a durable decision changes, update both files",
            agents,
        )
        _say("AGENTS.md tells agents to update MEMORY.md and DECISIONS.md when a durable decision changes")
        self.assertIn("stays binding until a later entry supersedes it", agents)
        _say("AGENTS.md states an accepted decision stays binding until superseded")

    def test_memory_is_current_state_index(self):
        memory = self.text["MEMORY.md"]
        self.assertIn("Current-state index", memory)
        self.assertIn("not a session transcript", memory)
        self.assertIn("not a second contract", memory)
        _say("MEMORY.md is a current-state index, not a session transcript or a second contract")
        self.assertIn("AGENTS.md", memory)
        self.assertIn("DECISIONS.md", memory)
        _say("MEMORY.md points at AGENTS.md and DECISIONS.md")
        for adr_id in ADR_TOPICS:
            self.assertIn(adr_id, memory, f"MEMORY.md does not index {adr_id}")
            _say(f"MEMORY.md indexes {adr_id}")
        self.assertIn("talks", memory)
        self.assertIn("GnuCOBOL 3.2", memory)
        self.assertIn("Bookworm", memory)
        self.assertIn("libpq", memory)
        self.assertIn("libgmp", memory)
        self.assertIn("-free", memory)
        _say("MEMORY.md records talks, both compiler facts, libpq, libgmp, and -free")

    def test_decisions_are_adrs(self):
        decisions = self.text["DECISIONS.md"]
        self.assertIn("An accepted entry stays binding until a later entry supersedes it", decisions)
        _say("DECISIONS.md states an accepted entry stays binding until superseded")
        headings = re.findall(r"(?m)^## (ADR-\d+):", decisions)
        self.assertGreaterEqual(len(headings), len(ADR_TOPICS))
        _say(f"DECISIONS.md has {len(headings)} ADR entries")
        for adr_id, topics in ADR_TOPICS.items():
            self.assertIn(adr_id, headings, f"missing {adr_id}")
            body = _adr_body(decisions, adr_id)
            for field in ADR_FIELDS:
                self.assertIn(field, body, f"{adr_id} missing {field}")
                _say(f"{adr_id} has field {field.rstrip(':')}")
            self.assertRegex(body, r"(?i)Status:\s*accepted")
            _say(f"{adr_id} status is accepted")
            for topic in topics:
                self.assertIn(topic, body, f"{adr_id} missing topic {topic}")
                _say(f"{adr_id} covers {topic}")

    def test_readme_versions_and_packages(self):
        readme = self.text["README.md"]
        self.assertIn("GnuCOBOL 3.2", readme)
        _say("README names language version GnuCOBOL 3.2")
        self.assertIn("POSIX sockets", readme)
        _say("README names framework POSIX sockets")
        self.assertIsNone(
            FRAMEWORK_SEMVER.search(readme),
            "README invented a framework semver for POSIX sockets",
        )
        _say("README does not invent a POSIX sockets framework semver")
        self.assertIn("no package version", readme)
        _say("README states POSIX sockets have no package version")
        self.assertIn("libpq", readme)
        _say("README names package libpq")
        self.assertIn("libgmp", readme)
        _say("README names package libgmp")
        self.assertIn("libgmp10", readme)
        _say("README names the image package libgmp10")
        for banned in ("CRaC", "crac"):
            self.assertNotIn(banned, readme)
            _say(f"README does not mention {banned}")
        self.assertIn("Bookworm", readme)
        self.assertIn("gnucobol", readme)
        _say("README keeps image GnuCOBOL 3.2 and Bookworm gnucobol as two facts")

    def test_private_data_scan(self):
        for name, text in self.text.items():
            self.assertIsNone(
                PRIVATE_KEY.search(text),
                f"{name} contains a private-key block",
            )
            _say(f"private-data scan: {name} has no private-key block")
            self.assertIsNone(
                HOME_PATH.search(text),
                f"{name} contains a personal /home/ path",
            )
            _say(f"private-data scan: {name} has no personal /home/ path")
            self.assertIsNone(
                SECRET_PATH.search(text),
                f"{name} contains /run/secrets",
            )
            _say(f"private-data scan: {name} has no /run/secrets path")
            self.assertIsNone(
                PRIVATE_HOST.search(text),
                f"{name} contains a non-public hostname",
            )
            _say(f"private-data scan: {name} has no non-public hostname")
            self.assertIsNone(
                TOKEN_PREFIX.search(text),
                f"{name} contains a token-like prefix",
            )
            _say(f"private-data scan: {name} has no token-like prefix")
            for match in TOKEN_ASSIGN.finditer(text):
                value = match.group("value").rstrip(".,)")
                self.assertIn(
                    value,
                    ALLOWED_TOKEN_VALUES,
                    f"{name} assigns {match.group('name')}={value}",
                )
            _say(f"private-data scan: {name} has no non-dev token assignment")
            for stale in ("mongoose", "cJSON", "4017", "carolina_api.cob"):
                self.assertNotIn(stale, text, f"{name} contains stale fact {stale}")
            _say(f"private-data scan: {name} has no stale mongoose/cJSON/4017/carolina_api.cob fact")
        agents = self.text["AGENTS.md"]
        self.assertIn(
            "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev",
            agents,
        )
        self.assertIn("POLYGLOT_REGISTER_TOKEN", agents)
        self.assertRegex(agents, r"POLYGLOT_REGISTER_TOKEN` \| `dev`")
        _say("public starter examples remain: carolina_dev URL and POLYGLOT_REGISTER_TOKEN=dev")


def _adr_body(text: str, adr_id: str) -> str:
    match = re.search(
        rf"(?ms)^## {re.escape(adr_id)}:.*?(?=^## ADR-|\Z)",
        text,
    )
    if match is None:
        return ""
    return match.group(0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
