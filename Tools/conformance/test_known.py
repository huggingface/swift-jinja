"""Focused checks for boolean-as-number difference classification."""

import unittest

import known


class BooleanNumericTests(unittest.TestCase):
    def matches(self, template, context=None, jinja="True", swift="False", cls="a"):
        case = {"template": template, "context": context or {}, "mode": "default", "options": {}}
        predicate = next(fn for key, _, _, fn in known.RULES if key == "bool-number")
        return predicate(case, {"ok": True, "output": jinja},
                         {"ok": True, "output": swift} if cls == "a" else {"ok": False, "error": swift}, cls)

    def test_boolean_tests(self):
        self.assertTrue(self.matches("{{ false is equalto(0) }}"))
        self.assertTrue(self.matches("{{ (('' is not defined) is equalto(0)) }}"))
        self.assertTrue(self.matches("{{ true in range(1, 4) }}"))
        self.assertTrue(self.matches("{{ flag in range(1, 4) }}", {"flag": True}))

    def test_existing_nested_boolean_filters(self):
        self.assertTrue(self.matches("{{ l1|select('number')|list }}", {"l1": [True]}, "[True]", "[]"))
        self.assertFalse(self.matches("{{ l1|select('number')|list }}", {"l1": ["true"]}, "[True]", "[]"))

    def test_skipped_boolean_branch(self):
        template = '{%- if flag not in range(1, 4) %}{{ [][-1].get("k", {}) }}]\n{% endif %} | '
        self.assertTrue(self.matches(template, {"flag": True}, " | ", 'JinjaError: runtime("Cannot call non-function value")', "b"))
        self.assertFalse(self.matches(template, {"flag": 1}, " | ", 'JinjaError: runtime("Cannot call non-function value")', "b"))
        self.assertFalse(self.matches(template, {"flag": True}, "different", 'JinjaError: runtime("Cannot call non-function value")', "b"))
        self.assertFalse(self.matches(template.replace("1, 4", "2, 4"),
                                      {"flag": True}, " | ", 'JinjaError: runtime("Cannot call non-function value")', "b"))

    def test_branch_requires_runtime_evidence(self):
        template = '{% if flag not in range(1, 4) %}{{ "int" is filter }}{% endif %}'
        self.assertFalse(self.matches(template, {"flag": True}, "",
                                      'JinjaError: parser("Expected test name but found filter")', "b"))
        runtime_body = '{% if flag not in range(1, 4) %}{{ [][-1].get("k", {}) }}{% endif %}'
        for error in ['JinjaError: lexer("Invalid character")',
                      'JinjaError: parser("Expected test name but found filter")',
                      'JinjaError: runtime("Unrelated failure")']:
            self.assertFalse(self.matches(runtime_body, {"flag": True}, "", error, "b"))

    def test_unrelated_differences(self):
        self.assertFalse(self.matches("{{ flag in range(1, 4) }}", {"flag": "true"}))
        self.assertFalse(self.matches("{{ flag is equalto(0) }}", {"flag": 0}))
        self.assertFalse(self.matches("{{ {'a': 10}|list }}", jinja="['a']", swift="[10]"))
        self.assertFalse(self.matches("{{ true in range(1, 4) }}", jinja="unrelated"))


class FixedDifferenceTests(unittest.TestCase):
    def label(self, template, jinja, swift, context=None, cls="a"):
        case = {"template": template, "context": context or {}, "mode": "default", "options": {}}
        return known.label(case, {"ok": True, "output": jinja},
                           {"ok": True, "output": swift} if cls == "a"
                           else {"ok": False, "error": swift}, cls)

    def test_dictionary_list_regression_is_unlabeled(self):
        self.assertIsNone(self.label("{{ {'a': 10}|list }}", "['a']", "[10]"))
        self.assertIsNone(self.label("{{ {'a': 10}|list }}", "['a']",
                                    'JinjaError: runtime("Unrelated failure")', cls="b"))

    def test_sort_missing_attributes_keeps_its_own_label(self):
        error = 'JinjaError: runtime("Cannot compare values of different types ( and )")'
        self.assertEqual(self.label("{{ {'a': 1, 'b': 2}|list|sort(attribute='k') }}",
                                    "['a', 'b']", error, cls="b"), "sort-undefined")
        self.assertEqual(self.label("{{ [missing, missing]|sort }}",
                                    "[Undefined, Undefined]", error, cls="b"), "sort-undefined")
        self.assertIsNone(self.label("{{ {'a': 1}|list }}", "['a']", error, cls="b"))

    def test_other_fixed_differences_are_unlabeled(self):
        self.assertIsNone(self.label("{{ true|int }}", "1", "0"))
        self.assertIsNone(self.label("{{ missing is sequence }}", "True", "False"))
        self.assertIsNone(self.label("{{ 2 in ['a', 2] }}", "True",
                                    'JinjaError: runtime("Cannot compare values of different types (a and 2)")', cls="b"))

    def test_undefined_membership_operator_is_fixed(self):
        error = 'JinjaError: runtime("Cannot compare values of different types (1 and )")'
        self.assertIsNone(self.label("{{ missing in [1] }}", "False", error, cls="b"))
        self.assertEqual(self.label("{{ missing is in([1]) }}", "False", error, cls="b"),
                         "in-undefined")

    def test_in_test_difference_remains_labeled(self):
        self.assertEqual(self.label("{{ 2 is in(['a', 2]) }}", "True",
                                    'JinjaError: runtime("Cannot compare values of different types (a and 2)")', cls="b"),
                         "in-mixed-types")


if __name__ == "__main__":
    unittest.main()
