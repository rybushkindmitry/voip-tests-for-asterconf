#!/usr/bin/env python3
"""Человекочитаемая сводка JUnit-отчёта sipssert (report.xml).

Использование: python3 scripts/report.py [путь-к-report.xml]
"""
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1] if len(sys.argv) > 1 else "report.xml"
root = ET.parse(path).getroot()
suites = [root] if root.tag == "testsuite" else root.findall("testsuite")

total = failed = 0
for suite in suites:
    for case in suite.iter("testcase"):
        total += 1
        name = case.get("name", "?")
        failure = case.find("failure") is not None or case.find("error") is not None
        if failure:
            failed += 1
            node = case.find("failure") if case.find("failure") is not None else case.find("error")
            msg = (node.get("message", "") or "") if node is not None else ""
            print(f"FAIL  {name}: {msg[:120]}")
        else:
            print(f"PASS  {name}")

print(f"\nИтого: {total - failed}/{total} passed, {failed} failed")
sys.exit(1 if failed else 0)
