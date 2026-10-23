"""Preparation inventory regression only, without Docker/root/APT qualification."""

from pathlib import Path
from contextlib import redirect_stderr
import io
import runpy
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from ci import prepare_recipes


class PreparationSourcesTest(unittest.TestCase):
    def test_failed_cli_forwards_only_registered_source_locations(self):
        errors = (b'private marker or command data\n'
                  b'APT_PREPARE_LOCATION serverdeck_executor/apt.py:123\n'
                  b'APT_PREPARE_LOCATION /private/input.py:4\n'
                  b'APT_PREPARE_LOCATION serverdeck_executor/apt.py:123 extra\n')
        output = io.StringIO()
        with patch.object(prepare_recipes.subprocess, 'run', return_value=
                          SimpleNamespace(returncode=1, stdout=b'', stderr=errors)), redirect_stderr(output):
            with self.assertRaises(ValueError):
                prepare_recipes.command(['fixed-cli'], preparation_diagnostics=True)
        self.assertEqual(output.getvalue(), 'APT_PREPARE_LOCATION serverdeck_executor/apt.py:123\n')

    def test_locations_exclude_exception_text_and_unregistered_paths(self):
        executor = Path(__file__).resolve().parents[1]
        script = runpy.run_path(str(executor / 'packaging/prepare-apt.py'))
        for filename, expected in ((str(executor / 'serverdeck_executor/apt.py'),
                                    ['APT_PREPARE_LOCATION serverdeck_executor/apt.py:1']),
                                   ('/private/unregistered.py', [])):
            try:
                exec(compile("raise ValueError('private marker')", filename, 'exec'), {})
            except ValueError as error:
                self.assertEqual(script['diagnostic_locations'](error), expected)

    def test_generator_change_changes_retained_source_identity(self):
        executor = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='serverdeck-recipe-sources-') as name:
            root = Path(name)
            paths = ['packaging/prepare-apt.py', 'requirements.lock',
                     'packaging/serverdeck-executor-bridge', 'ci/Dockerfile',
                     'ci/prepare_recipes.py', 'recipes/preparation-request.json',
                     'ci/apt.sources.list']
            paths += ['serverdeck_executor/' + path.name
                      for path in (executor / 'serverdeck_executor').glob('*.py')]
            for relative in paths:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((executor / relative).read_bytes())

            def read(relative, maximum):
                value = (root / relative).read_bytes()
                self.assertLessEqual(len(value), maximum)
                return value

            with patch.object(prepare_recipes, 'SOURCE', root):
                before = prepare_recipes.source_inputs(read)
                self.assertEqual(set(before), set(paths))
                generator = root / 'packaging/prepare-apt.py'
                generator.write_bytes(generator.read_bytes() + b'\n# changed preparation input\n')
                after = prepare_recipes.source_inputs(read)
            self.assertNotEqual(before['packaging/prepare-apt.py'], after['packaging/prepare-apt.py'])
            self.assertEqual([key for key in before if before[key] != after[key]],
                             ['packaging/prepare-apt.py'])


if __name__ == '__main__':
    unittest.main()
