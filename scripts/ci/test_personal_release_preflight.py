"""使用离线 API 样本测试工作流中的实际 Release 权限预检，不读取任何凭据。"""

import contextlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch
import urllib.error


WORKFLOW = Path(__file__).resolve().parents[2] / ".github/workflows/personal-dev-apk.yaml"
REPOSITORY = "handsomelong922/fluxdo"
API_ROOT = f"https://api.github.com/repos/{REPOSITORY}"
TARGET = "1" * 40
DEFAULT = "2" * 40
TARGET_ROOT = "3" * 40
DEFAULT_ROOT = "4" * 40
TARGET_GITHUB = "5" * 40
DEFAULT_GITHUB = "6" * 40
WORKFLOWS = "7" * 40
OTHER_WORKFLOWS = "8" * 40
ARTIFACT_URL = f"https://github.com/{REPOSITORY}/actions/runs/123/artifacts/456"


def tree_entry(path, sha):
    return {"path": path, "type": "tree", "mode": "040000", "sha": sha}


def tree(sha, entries):
    return {"sha": sha, "tree": entries, "truncated": False}


def fixture():
    return {
        "": {"full_name": REPOSITORY, "default_branch": "main"},
        f"git/commits/{TARGET}": {"sha": TARGET, "tree": {"sha": TARGET_ROOT}},
        "commits/main": {"sha": DEFAULT, "commit": {"tree": {"sha": DEFAULT_ROOT}}},
        f"git/trees/{TARGET_ROOT}": tree(TARGET_ROOT, [tree_entry(".github", TARGET_GITHUB)]),
        f"git/trees/{DEFAULT_ROOT}": tree(DEFAULT_ROOT, [tree_entry(".github", DEFAULT_GITHUB)]),
        f"git/trees/{TARGET_GITHUB}": tree(TARGET_GITHUB, [tree_entry("workflows", WORKFLOWS)]),
        f"git/trees/{DEFAULT_GITHUB}": tree(DEFAULT_GITHUB, [tree_entry("workflows", WORKFLOWS)]),
    }


class ReleasePreflightTest(unittest.TestCase):
    def run_preflight(self, responses, **overrides):
        workflow = WORKFLOW.read_text()
        match = re.search(
            r"      - name: Check GITHUB_TOKEN release eligibility\n"
            r"(?:(?!      - name:).)*?          python3 - <<'PY'\n"
            r"(.*?)^          PY$",
            workflow,
            re.M | re.S,
        )
        self.assertIsNotNone(match, "工作流缺少可独立验证的 Release 权限预检")
        source = textwrap.dedent(match.group(1))
        self.requests = []
        self.output = ""
        self.summary = ""
        stdout = io.StringIO()

        def urlopen(request, timeout):
            self.assertEqual(request.get_header("Authorization"), "Bearer offline-test-placeholder")
            self.assertEqual(request.get_method(), "GET", "预检不能写入外部状态")
            self.assertIsNone(request.data)
            self.assertEqual(timeout, 30)
            prefix = API_ROOT + "/"
            self.assertTrue(request.full_url == API_ROOT or request.full_url.startswith(prefix))
            path = request.full_url.removeprefix(API_ROOT).lstrip("/")
            self.requests.append(path)
            self.assertIn(path, responses, f"未预期的 API 请求：{path}")
            response = responses[path]
            if isinstance(response, Exception):
                raise response
            return io.BytesIO(json.dumps(response).encode())

        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "output"
            summary = Path(temp) / "summary"
            environment = {
                "GH_TOKEN": "offline-test-placeholder",
                "GITHUB_REPOSITORY": REPOSITORY,
                "GITHUB_SHA": TARGET,
                "GITHUB_REF": "refs/heads/dev",
                "RELEASE_PAT": "",
                "ARTIFACT_URL": ARTIFACT_URL,
                "GITHUB_OUTPUT": str(output),
                "GITHUB_STEP_SUMMARY": str(summary),
            }
            environment.update(overrides)
            try:
                with patch.dict(os.environ, environment), patch("urllib.request.urlopen", urlopen):
                    with contextlib.redirect_stdout(stdout):
                        exec(compile(source, str(WORKFLOW), "exec"), {"__name__": "__main__"})
            finally:
                self.output = output.read_text() if output.exists() else ""
                self.summary = summary.read_text() if summary.exists() else ""
                self.stdout = stdout.getvalue()

    def test_identical_workflow_tree_allows_existing_publish_step(self):
        self.run_preflight(fixture())
        self.assertEqual(self.output, "eligible=true\n")
        self.assertNotIn("Release 已创建", self.summary)
        self.assertNotIn("::warning::", self.stdout)
        self.assertIn(DEFAULT, self.summary)
        self.assertIn(ARTIFACT_URL, self.summary)

    def test_different_workflow_tree_explicitly_skips_without_publication(self):
        responses = fixture()
        responses[f"git/trees/{TARGET_GITHUB}"]["tree"][0]["sha"] = OTHER_WORKFLOWS
        self.run_preflight(responses)
        self.assertEqual(self.output, "eligible=false\n")
        self.assertIn("Release 未创建，权限预检跳过", self.summary)
        self.assertIn("::warning::", self.stdout)
        self.assertIn("Workflows", self.summary)
        self.assertIn(ARTIFACT_URL, self.summary)
        self.assertNotIn("Release 已创建", self.summary)

    def test_new_workflow_directory_skips(self):
        responses = fixture()
        responses[f"git/trees/{DEFAULT_GITHUB}"]["tree"] = []
        self.run_preflight(responses)
        self.assertEqual(self.output, "eligible=false\n")

    def test_missing_github_directory_is_a_real_tree_difference(self):
        responses = fixture()
        responses[f"git/trees/{DEFAULT_ROOT}"]["tree"] = []
        self.run_preflight(responses)
        self.assertEqual(self.output, "eligible=false\n")

    def test_both_workflow_directories_absent_allows_publication(self):
        responses = fixture()
        for sha in (TARGET_GITHUB, DEFAULT_GITHUB):
            responses[f"git/trees/{sha}"]["tree"] = []
        self.run_preflight(responses)
        self.assertEqual(self.output, "eligible=true\n")

    def test_api_failures_never_become_a_successful_skip(self):
        for status in (403, 404, 429, 500):
            with self.subTest(status=status):
                responses = fixture()
                responses[f"git/trees/{DEFAULT_GITHUB}"] = urllib.error.HTTPError(
                    API_ROOT, status, "offline error fixture", {}, None
                )
                with self.assertRaises(urllib.error.HTTPError):
                    self.run_preflight(responses)
                self.assertEqual(self.output, "")
                self.assertNotIn("权限预检跳过", self.summary)

    def test_truncated_tree_fails_closed(self):
        responses = fixture()
        responses[f"git/trees/{TARGET_ROOT}"]["truncated"] = True
        with self.assertRaisesRegex(SystemExit, "不完整"):
            self.run_preflight(responses)
        self.assertEqual(self.output, "")

    def test_non_directory_workflow_path_fails_closed(self):
        responses = fixture()
        responses[f"git/trees/{TARGET_GITHUB}"]["tree"][0]["type"] = "blob"
        with self.assertRaisesRegex(SystemExit, "目录"):
            self.run_preflight(responses)
        self.assertEqual(self.output, "")

    def test_wrong_commit_response_fails_closed(self):
        responses = fixture()
        responses[f"git/commits/{TARGET}"]["sha"] = DEFAULT
        with self.assertRaisesRegex(SystemExit, "提交"):
            self.run_preflight(responses)
        self.assertEqual(self.output, "")

    def test_default_branch_is_read_from_repository_metadata(self):
        responses = fixture()
        responses[""]["default_branch"] = "stable/base"
        responses["commits/stable%2Fbase"] = responses.pop("commits/main")
        self.run_preflight(responses)
        self.assertEqual(self.output, "eligible=true\n")
        self.assertIn("commits/stable%2Fbase", self.requests)

    def test_existing_pat_allows_different_workflows_without_exposing_secret(self):
        responses = fixture()
        responses[f"git/trees/{TARGET_GITHUB}"]["tree"][0]["sha"] = OTHER_WORKFLOWS
        sentinel = "offline-secret-sentinel"
        self.run_preflight(responses, RELEASE_PAT=sentinel)
        self.assertEqual(self.output, "eligible=true\n")
        self.assertIn("RELEASE_PAT", self.summary)
        self.assertNotIn("Release 已创建", self.summary)
        self.assertNotIn(sentinel, self.output + self.summary + self.stdout)
        self.assertIn(f"git/commits/{TARGET}", self.requests)
        self.assertFalse(any(path.startswith("git/trees/") for path in self.requests))

    def test_repository_ref_sha_and_artifact_guards_apply_to_both_credentials(self):
        for pat in ("", "offline-secret-sentinel"):
            for invalid in (
                {"GITHUB_REPOSITORY": "Lingyan000/fluxdo"},
                {"GITHUB_REF": "refs/heads/main"},
                {"GITHUB_SHA": "invalid"},
                {"ARTIFACT_URL": "https://github.com/Lingyan000/fluxdo/actions/runs/123"},
            ):
                with self.subTest(pat=bool(pat), invalid=invalid):
                    with self.assertRaises(SystemExit):
                        self.run_preflight(fixture(), RELEASE_PAT=pat, **invalid)
                    self.assertEqual(self.output, "")
                    self.assertEqual(self.requests, [])

    def test_pat_path_rejects_wrong_commit_and_api_failure(self):
        responses = fixture()
        responses[f"git/commits/{TARGET}"]["sha"] = DEFAULT
        with self.assertRaisesRegex(SystemExit, "提交"):
            self.run_preflight(responses, RELEASE_PAT="offline-secret-sentinel")
        responses[""] = urllib.error.HTTPError(API_ROOT, 403, "fixture", {}, None)
        with self.assertRaises(urllib.error.HTTPError):
            self.run_preflight(responses, RELEASE_PAT="offline-secret-sentinel")
        self.assertEqual(self.output, "")

    def test_publish_uses_existing_secret_and_honest_outcome_summaries(self):
        workflow = WORKFLOW.read_text()
        release = workflow.split("  release:\n", 1)[1]
        self.assertIn("token: ${{ secrets.RELEASE_PAT || github.token }}", release)
        self.assertIn("RELEASE_PAT: ${{ secrets.RELEASE_PAT }}", release)
        self.assertIn("repository: handsomelong922/fluxdo", release)
        self.assertIn("target_commitish: ${{ github.sha }}", release)
        self.assertIn("prerelease: true", release)
        self.assertIn("make_latest: false", release)
        self.assertIn("if: steps.publish.outcome == 'success'", release)
        self.assertIn("if: always() && steps.publish.outcome == 'failure'", release)
        self.assertIn("Release 发布失败", release)
        self.assertIn("Contents", release)
        self.assertNotIn("continue-on-error:", workflow)

    def test_summary_scripts_report_only_the_actual_publication_outcome(self):
        workflow = WORKFLOW.read_text()
        for name, url, expected_status in (
            ("Report the published release", "", 1),
            ("Report the published release", f"https://github.com/{REPOSITORY}/releases/tag/test", 0),
            ("Report a failed release without hiding the failure", "", 0),
        ):
            with self.subTest(name=name, url=url):
                block = workflow.split(f"      - name: {name}\n", 1)[1].split("      - name:", 1)[0]
                script = textwrap.dedent(block.split("        run: |\n", 1)[1])
                with tempfile.TemporaryDirectory() as temp:
                    summary = Path(temp) / "summary"
                    result = subprocess.run(
                        ["bash", "-e", "-o", "pipefail", "-c", script],
                        env={**os.environ, "GITHUB_STEP_SUMMARY": str(summary),
                             "RELEASE_URL": url, "ARTIFACT_URL": ARTIFACT_URL},
                        text=True, capture_output=True,
                    )
                    self.assertEqual(result.returncode, expected_status, result.stderr)
                    report = summary.read_text() if summary.exists() else ""
                    if "failed" in name:
                        self.assertIn("Release 发布失败", report)
                        self.assertIn(ARTIFACT_URL, report)
                        self.assertNotIn("Release 已创建", report)
                    elif url:
                        self.assertIn("Release 已创建", report)
                        self.assertIn(url, report)
                    else:
                        self.assertEqual(report, "")

    def test_workflow_keeps_hard_gates_and_conditionally_publishes(self):
        workflow = WORKFLOW.read_text()
        self.assertNotIn("continue-on-error:", workflow)
        self.assertIn("if: steps.release_permission.outputs.eligible == 'true'", workflow)
        self.assertIn("artifact_url: ${{ steps.upload_apk.outputs.artifact-url }}", workflow)
        self.assertIn("needs: build", workflow)
        self.assertIn("run: sha256sum -c fluxdo-personal-arm64-v8a.apk.sha256", workflow)
        self.assertLess(workflow.index("Verify the downloaded checksum"),
                        workflow.index("Check GITHUB_TOKEN release eligibility"))
        self.assertLess(workflow.index("Verify APK contents, signature and checksum"),
                        workflow.index("Upload verified APK"))


if __name__ == "__main__":
    unittest.main()
