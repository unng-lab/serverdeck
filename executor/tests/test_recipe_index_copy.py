"""Actual bounded file-copy regressions, without root/APT qualification."""
import hashlib
import os
import tempfile
import unittest
from unittest.mock import patch

from ci import prepare_recipes


class IndexCopyTest(unittest.TestCase):
    def test_multiple_chunks_keep_exact_bytes_and_bounded_reads(self):
        data = b'x' * (2 * prepare_recipes.COPY_CHUNK + 13)
        with tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as target:
            source.write(data)
            source.flush()
            source.seek(0)
            read = os.read
            with patch.object(prepare_recipes.os, 'read', wraps=read) as calls:
                count = prepare_recipes.copy_index_stream(source.fileno(), target.fileno(),
                    len(data), hashlib.sha256(data).hexdigest())
            self.assertEqual(count, len(data))
            self.assertTrue(all(call.args[1] <= prepare_recipes.COPY_CHUNK for call in calls.call_args_list))
            self.assertGreaterEqual(len(calls.call_args_list), 4)
            target.seek(0)
            self.assertEqual(target.read(), data)

    def test_wrong_length_or_digest_cannot_succeed(self):
        for expected_size, digest in ((3, hashlib.sha256(b'abc').hexdigest()),
                                      (5, hashlib.sha256(b'abcd').hexdigest()), (4, '0' * 64)):
            with self.subTest(size=expected_size), tempfile.TemporaryFile() as source, tempfile.TemporaryFile() as target:
                source.write(b'abcd')
                source.flush()
                source.seek(0)
                with self.assertRaises(ValueError):
                    prepare_recipes.copy_index_stream(source.fileno(), target.fileno(), expected_size, digest)

    def test_excessive_expected_size_is_rejected_before_read(self):
        with patch.object(prepare_recipes.os, 'read', side_effect=AssertionError('UNEXPECTED_READ')):
            with self.assertRaises(ValueError):
                prepare_recipes.copy_index_stream(-1, -1, prepare_recipes.MAX_INDEX_BYTES + 1, '0' * 64)


if __name__ == '__main__':
    unittest.main()
