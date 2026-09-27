import unittest

from zig_jupyter_kernel.natural_syntax import (
    NaturalDeclaration,
    NaturalUpdate,
    expression_identifiers,
    parse_declaration,
    parse_inspection,
    parse_update,
    render_native_declaration_with_bindings,
    render_native_update,
    transform_natural_source,
)


class NaturalSyntaxTests(unittest.TestCase):

    def test_parse_i64(self):
        self.assertEqual(
            parse_declaration(
                "var age: i64 = 20;"
            ),
            NaturalDeclaration(
                name="age",
                type_name="i64",
                value_source="20",
            ),
        )

    def test_parse_f64(self):
        self.assertEqual(
            parse_declaration(
                "var score: f64 = 98.5;"
            ),
            NaturalDeclaration(
                name="score",
                type_name="f64",
                value_source="98.5",
            ),
        )

    def test_parse_bool(self):
        self.assertEqual(
            parse_declaration(
                "var enabled: bool = true;"
            ),
            NaturalDeclaration(
                name="enabled",
                type_name="bool",
                value_source="true",
            ),
        )

    def test_transform_i64_literal(self):
        result = transform_natural_source(
            "var age: i64 = 20;"
        )

        self.assertIn(
            "ziglab.setI64",
            result,
        )

    def test_transform_f64_literal(self):
        result = transform_natural_source(
            "var score: f64 = 98.5;"
        )

        self.assertIn(
            "ziglab.setF64",
            result,
        )

    def test_transform_bool_literal(self):
        result = transform_natural_source(
            "var enabled: bool = true;"
        )

        self.assertIn(
            "ziglab.setBool",
            result,
        )

    def test_normal_zig_not_claimed(self):
        self.assertIsNone(
            transform_natural_source(
                'std.debug.print("hello", .{});'
            )
        )

    def test_function_not_claimed(self):
        self.assertIsNone(
            transform_natural_source(
                """
fn hello() void {
}
"""
            )
        )

    def test_parse_update(self):
        self.assertEqual(
            parse_update(
                "age += 1;"
            ),
            NaturalUpdate(
                name="age",
                operator="+=",
                value_source="1",
            ),
        )

    def test_parse_f64_update(self):
        self.assertEqual(
            parse_update(
                "score += 1.5;"
            ),
            NaturalUpdate(
                name="score",
                operator="+=",
                value_source="1.5",
            ),
        )

    def test_render_i64_update(self):
        update = parse_update(
            "age += 1;"
        )

        result = render_native_update(
            update,
            "i64",
        )

        self.assertIn(
            "ziglab.getI64",
            result,
        )

        self.assertIn(
            "ziglab.setI64",
            result,
        )

    def test_render_f64_update(self):
        update = parse_update(
            "score += 1.5;"
        )

        result = render_native_update(
            update,
            "f64",
        )

        self.assertIn(
            "ziglab.getF64",
            result,
        )

        self.assertIn(
            "ziglab.setF64",
            result,
        )

    def test_bool_update_rejected(self):
        update = parse_update(
            "enabled += 1;"
        )

        with self.assertRaises(
            ValueError
        ):
            render_native_update(
                update,
                "bool",
            )

    def test_expression_identifiers(self):
        self.assertEqual(
            expression_identifiers(
                "age + bonus"
            ),
            (
                "age",
                "bonus",
            ),
        )

    def test_literals_have_no_references(self):
        self.assertEqual(
            expression_identifiers(
                "20 + 5"
            ),
            (),
        )

        self.assertEqual(
            expression_identifiers(
                "true"
            ),
            (),
        )

    def test_render_bound_declaration(self):
        declaration = parse_declaration(
            "var total: i64 = age + bonus;"
        )

        result = (
            render_native_declaration_with_bindings(
                declaration,
                {
                    "age": "i64",
                    "bonus": "i64",
                },
            )
        )

        self.assertIn(
            'ziglab.getI64',
            result,
        )

        self.assertIn(
            '__ziglab_ref_age',
            result,
        )

        self.assertIn(
            '__ziglab_ref_bonus',
            result,
        )

        self.assertIn(
            'ziglab.setI64',
            result,
        )

    def test_render_bool_reference(self):
        declaration = parse_declaration(
            "var copy: bool = enabled;"
        )

        result = (
            render_native_declaration_with_bindings(
                declaration,
                {
                    "enabled": "bool",
                },
            )
        )

        self.assertIn(
            "ziglab.getBool",
            result,
        )

        self.assertIn(
            "ziglab.setBool",
            result,
        )

    def test_update_can_reference_variable(self):
        update = parse_update(
            "age += bonus;"
        )

        result = render_native_update(
            update,
            "i64",
            {
                "bonus": "i64",
            },
        )

        self.assertIn(
            '__ziglab_ref_bonus',
            result,
        )


    def test_parse_inspection(self):
        self.assertEqual(
            parse_inspection("age"),
            "age",
        )

    def test_parse_inspection_with_semicolon(self):
        self.assertEqual(
            parse_inspection("score;"),
            "score",
        )

    def test_bool_literal_not_inspection(self):
        self.assertIsNone(
            parse_inspection("true")
        )



if __name__ == "__main__":
    unittest.main()
