"""Signed release date boundaries, without network/root or fake APT trust.

These exercise only time policy; actual signatures, sandbox readability and
package transactions remain mandatory integration acceptance.
"""
import datetime as dt
from email.utils import format_datetime
import unittest

from serverdeck_executor.apt import _validate_release_time
from serverdeck_executor.codec import Rejected


class ReleaseTimeTest(unittest.TestCase):
    now = dt.datetime(2026, 10, 23, 12, tzinfo=dt.timezone.utc)

    def release(self, published, expires=None):
        result = 'Date: ' + format_datetime(published) + '\n'
        if expires is not None:
            result += 'Valid-Until: ' + format_datetime(expires) + '\n'
        return result

    def test_immutable_noble_base_is_not_expired_by_unsigned_local_age_rule(self):
        # Actual Ubuntu noble base Release Date, not a rotating update index.
        _validate_release_time('Date: Thu, 25 Apr 2024 15:10:33 UTC\n', self.now)

    def test_signed_expiry_is_enforced_at_exact_boundary(self):
        date = self.now - dt.timedelta(days=2)
        for expiry in [self.now - dt.timedelta(seconds=1), self.now, date]:
            with self.subTest(expiry=expiry), self.assertRaises(Rejected) as caught:
                _validate_release_time(self.release(date, expiry), self.now)
            self.assertEqual(caught.exception.code, 'QUALIFICATION_REQUIRED')
        _validate_release_time(self.release(date, self.now + dt.timedelta(seconds=1)), self.now)

    def test_future_clock_skew_is_bounded(self):
        _validate_release_time(self.release(self.now + dt.timedelta(seconds=300)), self.now)
        with self.assertRaises(Rejected):
            _validate_release_time(self.release(self.now + dt.timedelta(seconds=301)), self.now)

    def test_missing_duplicate_naive_or_malformed_dates_refuse(self):
        valid = self.release(self.now)
        for body in ['', 'Date: nonsense\n', 'Date: Fri, 23 Oct 2026 12:00:00\n',
                     valid + valid, valid + 'Valid-Until: nonsense\n',
                     valid + 'Valid-Until: \n', valid + 'valid-until:\n',
                     valid + 'Valid-Until: Fri, 23 Oct 2026 13:00:00\n',
                     valid + 'Valid-Until: Sat, 24 Oct 2026 12:00:00 UTC\n' * 2]:
            with self.subTest(body=body), self.assertRaises(Rejected):
                _validate_release_time(body, self.now)

    def test_signed_fields_are_case_insensitive(self):
        with self.assertRaises(Rejected):
            _validate_release_time(self.release(
                self.now - dt.timedelta(days=2), self.now
            ).lower(), self.now)


if __name__ == '__main__':
    unittest.main()
