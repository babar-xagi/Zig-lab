import unittest

from zig_jupyter_kernel.natural_syntax import (
    NaturalDeclaration,
    NaturalUpdate,
    parse_declaration,
    parse_update,
    render_native_update,
    transform_natural_source,
)


class NaturalSyntaxTests(unittest.TestCase):

    def test_parse_i64(self):
        result = parse_declaration(
            "var age: i64 = 20;"
        )

        self.assertEqual(
            result,
            NaturalDeclaration(
                name="age",
                type_name="i64",
                value_source="20",
            ),
        )

    def test_parse_f64(self):
        result = parse_declaration(
            "var score: f64 = 98.5;"
        )

        self.assertEqual(
            result,
            NaturalDeclaration(
                name="score",
                type_name="f64",
                value_source="98.5",
            ),
        )

    def test_parse_bool(self):
        result = parse_declaration(
            "var enabled: bool = true;"
        )

        self.assertEqual(
            result,
            NaturalDeclaration(
                name="enabled",
                type_name="bool",
                value_source="true",
            ),
        )

    def test_transform_i64(self):
        result = transform_natural_source(
            "var age: i64 = 20;"
        )

        self.assertIn(
            "ziglab.setI64",
            result,
        )

    def test_transform_f64(self):
        result = transform_natural_source(
            "var score: f64 = 98.5;"
        )

        self.assertIn(
            "ziglab.setF64",
            result,
        )

    def test_transform_bool(self):
        result = transform_natural_source(
            "var enabled: bool = true;"
        )

        self.assertIn(
            "ziglab.setBool",
            result,
        )

    def test_normal_zig_not_claimed(self):
        result = transform_natural_source(
            'std.debug.print("hello", .{});'
        )

        self.assertIsNone(result)

    def test_function_not_claimed(self):
        result = transform_natural_source(
            """
fn hello() void {
}
"""
        )

        self.assertIsNone(result)

    def test_parse_update(self):
        result = parse_update(
            "age += 1;"
        )

        self.assertEqual(
            result,
            NaturalUpdate(
                name="age",
                operator="+=",
                value_source="1",
            ),
        )

    def test_parse_f64_update(self):
        result = parse_update(
            "score += 1.5;"
        )

        self.assertEqual(
            result,
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

        with self.assertRaises(ValueError):
            render_native_update(
                update,
                "bool",
            )


if __name__ == "__main__":
    unittest.main()
