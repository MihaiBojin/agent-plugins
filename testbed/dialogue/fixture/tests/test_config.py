import unittest

from app.config import load_config


class LoadConfigTest(unittest.TestCase):
    def test_missing_file_returns_defaults(self):
        self.assertEqual(load_config("does-not-exist.json")["port"], 8080)


if __name__ == "__main__":
    unittest.main()
