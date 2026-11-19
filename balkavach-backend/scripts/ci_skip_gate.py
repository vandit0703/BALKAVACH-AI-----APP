"""Fail CI when the DB-backed suite silently skips: ``python scripts/ci_skip_gate.py junit.xml``.

A skipped database test means the disposable database is stale or missing a migration, which
is exactly how ~160 tests went unexercised before. ``MAX_SKIPPED_TESTS`` (default 0) lists how
many documented skips are tolerated.
"""

import os
import sys
from defusedxml import ElementTree as ET


def main(path: str) -> int:
	root = ET.parse(path).getroot()
	suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
	skipped = sum(int(s.get("skipped", 0)) for s in suites)
	failed = sum(int(s.get("failures", 0)) + int(s.get("errors", 0)) for s in suites)
	total = sum(int(s.get("tests", 0)) for s in suites)
	allowed = int(os.environ.get("MAX_SKIPPED_TESTS", "0"))
	print(f"tests={total} failed={failed} skipped={skipped} (allowed skips: {allowed})")
	if skipped > allowed:
		for case in root.iter("testcase"):
			skip = case.find("skipped")
			if skip is not None:
				print(f"  SKIPPED {case.get('classname')}::{case.get('name')}: {skip.get('message', '')}")
		print("Too many skipped tests: the database-backed suite did not run.")
		return 1
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1]))
