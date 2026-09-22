#!/usr/bin/env python3
"""Read the shipped Gitea workflow and assert prepare-then-parallel-checks."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".gitea" / "workflows" / "precommit.yml"
HELPER = ROOT / "scripts" / "ci-env.sh"
PRECOMMIT = ROOT / ".pre-commit-config.yaml"
HOOK = ROOT / ".githooks" / "pre-commit"

CLONE_CMD = (
    "git clone --depth 1 --no-checkout "
    '"https://x-access-token:${token}@${host}/${GITHUB_REPOSITORY}" .'
)
FETCH_CMD = 'git fetch --depth 1 origin "${GITHUB_SHA}"'
CHECK_JOBS = ("test", "sast", "audit", "gitleaks", "lint")
PREPARE_JOB = "prepare"
MAKE_TARGETS = {
    "test": "make test",
    "sast": "make sast",
    "audit": "make audit",
    "gitleaks": "make gitleaks",
    "lint": "make lint",
}
TOOLCHAIN_INSTALL = re.compile(
    r"apt-get[\s\S]{0,400}(?:gnucobol|\bgcc\b|libpq|clang-format)"
    r"|trivy_0\.74\.0"
    r"|gitleaks_8\.30\.1"
    r"|aquasecurity/trivy"
    r"|gitleaks/gitleaks",
    re.I,
)


def _job_bodies(text: str) -> dict[str, str]:
    jobs: dict[str, str] = {}
    matches = list(re.finditer(r"^  ([A-Za-z0-9_-]+):\n", text, re.M))
    jobs_idx = text.find("\njobs:\n")
    if jobs_idx < 0:
        jobs_idx = text.find("jobs:\n")
    if jobs_idx < 0:
        return jobs
    for i, match in enumerate(matches):
        if match.start() < jobs_idx:
            continue
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        jobs[match.group(1)] = text[start:end]
    return jobs


class WorkflowGraphTests(unittest.TestCase):
    def test_gitea_workflow_is_prepare_then_parallel_checks(self):
        self.assertTrue(WORKFLOW.is_file(), "missing .gitea/workflows/precommit.yml")
        self.assertTrue(HELPER.is_file(), "missing scripts/ci-env.sh")
        text = WORKFLOW.read_text()
        helper = HELPER.read_text()

        self.assertNotRegex(text, r"(?m)^\s*git init\b")
        self.assertNotIn("git config --global init.defaultBranch", text)
        self.assertNotRegex(text, r"(?m)^\s*-\s*uses:\s*actions/checkout")
        self.assertNotIn("actions/upload-artifact@v4", text)
        self.assertNotIn("actions/download-artifact@v4", text)
        self.assertRegex(
            text,
            r"GITHUB_TOKEN:\s*\$\{\{\s*github\.token\s*\}\}",
            "job token must be passed so container git fetch can auth",
        )

        jobs = _job_bodies(text)
        self.assertEqual(
            set(jobs),
            {PREPARE_JOB, *CHECK_JOBS},
            f"jobs={sorted(jobs)}",
        )
        self.assertNotRegex(text, r"(?m)^\s+- run: pre-commit run")

        prep = jobs[PREPARE_JOB]
        self.assertIn(CLONE_CMD, prep)
        self.assertIn(FETCH_CMD, prep)
        self.assertIn("missing job token for git fetch", prep)
        self.assertIn("gnucobol", prep)
        self.assertRegex(prep, r"\bgcc\b")
        self.assertIn("libpq", prep)
        self.assertIn("clang-format", prep)
        self.assertIn("trivy_0.74.0", prep)
        self.assertIn("gitleaks_8.30.1", prep)
        self.assertIn("make", prep)
        self.assertIn("ci-env.sh prepare", prep)
        self.assertNotIn("needs:", prep)

        self.assertIn("cmd_pack", helper)
        self.assertIn("cmd_unpack", helper)
        self.assertIn("cmd_restore", helper)
        self.assertIn("cmd_prepare", helper)

        for name in CHECK_JOBS:
            body = jobs[name]
            self.assertIn(
                "needs: prepare",
                body,
                f"{name} must wait on the prepare job",
            )
            self.assertIn("ci-env.sh", body, f"{name} must restore via ci-env.sh")
            self.assertIn("restore", body, f"{name} must restore the prepared env")
            self.assertIn(
                MAKE_TARGETS[name],
                body,
                f"{name} must run {MAKE_TARGETS[name]}",
            )
            self.assertNotIn("git clone", body, f"{name} must not clone")
            self.assertNotIn(CLONE_CMD, body, f"{name} must not repeat the token clone")
            self.assertIsNone(
                TOOLCHAIN_INSTALL.search(body),
                f"{name} must not reinstall gnucobol/gcc/libpq/clang-format/trivy/gitleaks",
            )
            self.assertNotIn("gnucobol", body, f"{name} must not mention gnucobol")
            self.assertNotRegex(body, r"\bgcc\b", f"{name} must not mention gcc")
            self.assertNotIn("libpq", body, f"{name} must not mention libpq")
            self.assertNotIn("clang-format", body, f"{name} must not mention clang-format")
            self.assertNotIn("trivy", body, f"{name} must not mention trivy")
            for other in CHECK_JOBS:
                self.assertNotRegex(
                    body,
                    rf"(?m)^\s+needs:\s*{re.escape(other)}\s*$",
                    f"{name} must not needs: {other}",
                )

        self.assertIn("make test", jobs["test"])
        self.assertIn("make sast", jobs["sast"])
        self.assertIn("make audit", jobs["audit"])
        self.assertIn("make gitleaks", jobs["gitleaks"])
        self.assertIn("make lint", jobs["lint"])

    def test_local_gates_stay_five_named_checks(self):
        precommit = PRECOMMIT.read_text()
        hook = HOOK.read_text()
        for hook_id in ("local-tests", "sast", "audit", "gitleaks", "lint"):
            self.assertRegex(
                precommit,
                rf"(?m)^\s+- id: {re.escape(hook_id)}\s*$",
                f"pre-commit must include hook id {hook_id}",
            )
        self.assertIn("make test", hook)
        self.assertIn("make sast", hook)
        self.assertIn("make audit", hook)
        self.assertIn("make gitleaks", hook)
        self.assertIn("make lint", hook)


if __name__ == "__main__":
    unittest.main()
