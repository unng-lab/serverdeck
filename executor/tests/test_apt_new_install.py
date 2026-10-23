"""Pure APT flag-boundary regressions; not actual python3-apt resolution."""
from types import SimpleNamespace
import unittest

from serverdeck_executor.apt import _new_install_candidate
from serverdeck_executor.codec import Rejected


def fresh():
    return SimpleNamespace(shortname='postgresql-16', is_installed=False,
        has_config_files=False, marked_install=True, marked_upgrade=True,
        marked_delete=False, marked_downgrade=False, marked_reinstall=False,
        candidate=SimpleNamespace(downloadable=True, architecture='amd64',
                                  origins=[SimpleNamespace(trusted=True)]))


class NewInstallBoundaryTest(unittest.TestCase):
    def test_new_install_accepts_overlapping_libapt_upgrade_flag(self):
        package = fresh()
        for code in ('QUALIFICATION_REQUIRED', 'CONFLICT'):
            self.assertIs(_new_install_candidate(package, code), package.candidate)

    def test_existing_or_destructive_actions_refuse(self):
        for attribute in ('is_installed', 'has_config_files', 'marked_delete',
                          'marked_downgrade', 'marked_reinstall'):
            for code in ('QUALIFICATION_REQUIRED', 'CONFLICT'):
                with self.subTest(attribute=attribute, code=code):
                    package = fresh()
                    setattr(package, attribute, True)
                    with self.assertRaises(Rejected) as failure:
                        _new_install_candidate(package, code)
                    self.assertEqual(failure.exception.code, code)

    def test_no_new_install_mark_refuses(self):
        package = fresh()
        package.marked_install = False
        with self.assertRaises(Rejected):
            _new_install_candidate(package)

    def test_protected_and_untrusted_candidates_refuse(self):
        for change in ('netbird', 'architecture', 'downloadable', 'origins', 'untrusted', 'missing'):
            with self.subTest(change=change):
                package = fresh()
                if change == 'netbird':
                    package.shortname = 'netbird-agent'
                elif change == 'architecture':
                    package.candidate.architecture = 'arm64'
                elif change == 'downloadable':
                    package.candidate.downloadable = False
                elif change == 'origins':
                    package.candidate.origins = []
                elif change == 'untrusted':
                    package.candidate.origins[0].trusted = False
                else:
                    package.candidate = None
                with self.assertRaises(Rejected):
                    _new_install_candidate(package)


if __name__ == '__main__':
    unittest.main()
