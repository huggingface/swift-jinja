"""Focused checks for known-difference classification."""

import unittest

import known


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

    def test_sort_of_equal_missing_values_is_unlabeled(self):
        error = 'JinjaError: runtime("Cannot compare values of different types ( and )")'
        self.assertIsNone(self.label("{{ {'a': 1, 'b': 2}|list|sort(attribute='k') }}",
                                     "['a', 'b']", error, cls="b"))
        self.assertIsNone(self.label("{{ [missing, missing]|sort }}",
                                     "[Undefined, Undefined]", error, cls="b"))
        self.assertIsNone(self.label("{{ [none, none]|sort }}", "[None, None]",
                                     'JinjaError: runtime("Cannot compare values of different types (None and None)")',
                                     cls="b"))

    def test_other_fixed_differences_are_unlabeled(self):
        self.assertIsNone(self.label("{{ true|int }}", "1", "0"))
        self.assertIsNone(self.label("{{ true|float }}", "1.0", "0.0"))
        self.assertIsNone(self.label("{{ (1 > 0) is number }}", "True", "False"))
        self.assertIsNone(self.label("{{ 0 == false }}", "True", "False"))
        self.assertIsNone(self.label("{{ 1|filesizeformat }}", "1 Byte", "1 Bytes"))
        self.assertIsNone(self.label("{{ 1 < 2 == true }}", "False", "True"))
        self.assertIsNone(self.label("{{ missing is sequence }}", "True", "False"))
        self.assertIsNone(self.label("{{ 2 in ['a', 2] }}", "True",
                                    'JinjaError: runtime("Cannot compare values of different types (a and 2)")', cls="b"))

    def test_undefined_membership_operator_is_fixed(self):
        error = 'JinjaError: runtime("Cannot compare values of different types (1 and )")'
        self.assertIsNone(self.label("{{ missing in [1] }}", "False", error, cls="b"))
        self.assertEqual(self.label("{{ missing is in([1]) }}", "False", error, cls="b"),
                         "in-undefined")

    def test_namespace_regressions_are_unlabeled(self):
        for expression, jinja, swift in [
            ("n is sequence", "False", "True"),
            ("n is mapping", "False", "True"),
            ("n is iterable", "False", "True"),
            ("n is not iterable", "True", "False"),
            ("n.items is callable", "False", "True"),
            ("n.items is not callable", "True", "False"),
            ("n.items", "[]", "[Function]"),
        ]:
            expression = expression.replace("n.", "namespace(items=[]).").replace("n is", "namespace(items=[]) is")
            template = "{{ " + expression + " }}"
            with self.subTest(expression=expression):
                self.assertIsNone(self.label(template, jinja, swift))

    def test_undefined_iterability_is_fixed(self):
        self.assertIsNone(self.label("{{ missing is iterable }}", "True", "False"))
        self.assertIsNone(self.label("{{ missing is not iterable }}", "False", "True"))
        self.assertIsNone(self.label("{{ missing is callable }}", "False", "True"))

    def test_non_namespace_assignment_remains_labeled(self):
        case = {"template": "{% set x = {} %}{% set x.a = 1 %}{{ x.a }}",
                "context": {}, "mode": "default", "options": {}}
        jinja = {"ok": False, "error": "TemplateRuntimeError: cannot assign attribute on non-namespace object"}
        self.assertEqual(known.label(case, jinja, {"ok": True, "output": "1"}, "c"),
                         "ns-attr")

    def test_in_test_difference_remains_labeled(self):
        self.assertEqual(self.label("{{ 2 is in(['a', 2]) }}", "True",
                                    'JinjaError: runtime("Cannot compare values of different types (a and 2)")', cls="b"),
                         "in-mixed-types")


if __name__ == "__main__":
    unittest.main()
