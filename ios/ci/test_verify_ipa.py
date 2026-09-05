import struct
import unittest
from verify_ipa import inspect_executable


class ExecutableValidationTests(unittest.TestCase):
    def executable(self, platform=2, cpu=0x0100000C, filetype=2):
        return struct.pack('<8I', 0xFEEDFACF, cpu, 0, filetype, 1, 24, 0, 0) + struct.pack('<6I', 0x32, 24, platform, 0, 0, 0)

    def test_accepts_arm64_ios_device(self):
        self.assertEqual(inspect_executable(self.executable())['platform'], 'iOS device')

    def test_rejects_simulator_even_when_arm64(self):
        with self.assertRaisesRegex(ValueError, 'simulator'):
            inspect_executable(self.executable(platform=7))

    def test_rejects_renamed_html_download(self):
        with self.assertRaises(ValueError):
            inspect_executable(b'<html>download expired</html>')

    def test_rejects_library_in_place_of_app(self):
        with self.assertRaisesRegex(ValueError, 'not an application'):
            inspect_executable(self.executable(filetype=6))

    def test_rejects_truncated_binary(self):
        with self.assertRaisesRegex(ValueError, 'load commands'):
            inspect_executable(self.executable()[:-1])


if __name__ == '__main__':
    unittest.main()
