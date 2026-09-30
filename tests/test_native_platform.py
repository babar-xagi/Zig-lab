import unittest

from zig_jupyter_kernel.native_platform import (
    dynamic_library_name,
    native_platform,
    runtime_executable_name,
)


class NativePlatformTests(unittest.TestCase):

    def test_linux(self):
        target = native_platform("Linux")

        self.assertEqual(
            target.name,
            "linux",
        )

        self.assertEqual(
            target.dynamic_library_suffix,
            ".so",
        )

        self.assertEqual(
            target.executable_suffix,
            "",
        )

    def test_macos(self):
        target = native_platform("Darwin")

        self.assertEqual(
            target.name,
            "macos",
        )

        self.assertEqual(
            target.dynamic_library_suffix,
            ".dylib",
        )

    def test_windows(self):
        target = native_platform("Windows")

        self.assertEqual(
            target.name,
            "windows",
        )

        self.assertEqual(
            target.dynamic_library_suffix,
            ".dll",
        )

        self.assertEqual(
            target.executable_suffix,
            ".exe",
        )

    def test_runtime_names(self):
        self.assertEqual(
            runtime_executable_name("Linux"),
            "ziglab-runtime",
        )

        self.assertEqual(
            runtime_executable_name("Darwin"),
            "ziglab-runtime",
        )

        self.assertEqual(
            runtime_executable_name("Windows"),
            "ziglab-runtime.exe",
        )

    def test_library_names(self):
        self.assertEqual(
            dynamic_library_name(
                "ziglab-cell",
                "Linux",
            ),
            "ziglab-cell.so",
        )

        self.assertEqual(
            dynamic_library_name(
                "ziglab-cell",
                "Darwin",
            ),
            "ziglab-cell.dylib",
        )

        self.assertEqual(
            dynamic_library_name(
                "ziglab-cell",
                "Windows",
            ),
            "ziglab-cell.dll",
        )

    def test_unknown_platform(self):
        with self.assertRaises(
            RuntimeError
        ):
            native_platform(
                "UnknownOS"
            )


if __name__ == "__main__":
    unittest.main()
