"""Focused checks for boolean-as-number difference classification."""

import unittest

import known


class BooleanNumericTests(unittest.TestCase):
    def matches(self, template, context=None, jinja="True", swift="False", cls="a"):
        case = {"template": template, "context": context or {}, "mode": "default", "options": {}}
        predicate = next(fn for key, _, _, fn in known.RULES if key == "bool-number")
        return predicate(case, {"ok": True, "output": jinja},
                         {"ok": cls == "a", "output": swift}, cls)

    def test_boolean_tests(self):
        self.assertTrue(self.matches("{{ false is equalto(0) }}"))
        self.assertTrue(self.matches("{{ (('' is not defined) is equalto(0)) }}"))
        self.assertTrue(self.matches("{{ true in range(1, 4) }}"))
        self.assertTrue(self.matches("{{ flag in range(1, 4) }}", {"flag": True}))

    def test_skipped_boolean_branch(self):
        template = '{%- if flag not in range(1, 4) %}{{ [][-1].get("k", {}) }}]\n{% endif %} | '
        self.assertTrue(self.matches(template, {"flag": True}, " | ", "ERROR", "b"))
        self.assertFalse(self.matches(template, {"flag": 1}, " | ", "ERROR", "b"))
        self.assertFalse(self.matches(template, {"flag": True}, "different", "ERROR", "b"))
        self.assertFalse(self.matches(template.replace("1, 4", "2, 4"),
                                      {"flag": True}, " | ", "ERROR", "b"))

    def test_unrelated_differences(self):
        self.assertFalse(self.matches("{{ flag in range(1, 4) }}", {"flag": "true"}))
        self.assertFalse(self.matches("{{ flag is equalto(0) }}", {"flag": 0}))
        self.assertFalse(self.matches("{{ {'a': 10}|list }}", jinja="['a']", swift="[10]"))
        self.assertFalse(self.matches("{{ true in range(1, 4) }}", jinja="unrelated"))


if __name__ == "__main__":
    unittest.main()
