import unittest
from dependency_audit import components, scan


class DependencyAuditTest(unittest.TestCase):
    def test_public_versions_only(self):
        items = components({"packages": [
            {"name": "a", "version": "1.0.0", "source": "hosted"},
            {"name": "private", "version": "0.1", "source": "git"},
        ]}, [{"group": "g", "name": "b", "version": "2"}])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0][1], "g:b")

    def test_findings_need_review(self):
        items = [("Pub", "a", "1", "pkg:pub/a@1")]
        findings = scan(items, lambda _: {"results": [{"vulns": [{"id": "TEST-1"}]}]})
        self.assertEqual(findings[0]["status"], "needs-review")
        self.assertEqual(scan(items, lambda _: {"results": [{}]}), [])

    def test_incomplete_results_fail(self):
        with self.assertRaises(ValueError):
            scan([("Pub", "a", "1", "pkg:pub/a@1")], lambda _: {"results": []})
