"""Bounded strict JSON and the foundation canonical representation.

No exception contains the input document. Wire envelopes never accept floats,
duplicate keys, invalid Unicode or unknown fields.
"""

import hashlib
import json
import re
import struct
import unicodedata


class Rejected(Exception):
    def __init__(self, code="VALIDATION", retry=False, *, field=None):
        super().__init__(code)
        self.code, self.retry = code, retry
        self.field = field if field in {"executor", "runtime", "trust", "recipe", "packages", "paths",
            "qualification", "memory", "step_limit", "observation"} else None


def require(condition, code="VALIDATION"):
    if not condition:
        raise Rejected(code)


def fields(value, required, optional=()):
    require(type(value) is dict)
    require(set(required) <= value.keys() <= set(required) | set(optional))
    return value


def integer(value, minimum, maximum):
    require(type(value) is int and minimum <= value <= maximum)
    return value


def text(value, minimum=0, maximum=4096, public=False):
    require(type(value) is str and minimum <= len(value) <= maximum)
    require(not any(0xD800 <= ord(c) <= 0xDFFF for c in value))
    if public:
        require(unicodedata.normalize("NFC", value) == value)
        require(not any(ord(c) < 32 and c not in "\n\t" or 127 <= ord(c) <= 159 for c in value))
        require(not any(marker in value for marker in ("{{", "{%", "{#")))
    return value


def identifier(value):
    require(type(value) is str and re.fullmatch(r"[a-z][a-z0-9_]{0,31}", value))
    return value


def sha(value):
    require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value))
    return value


def uuid(value):
    require(type(value) is str and re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", value))
    return value


def _tree(value, depth=0, normalize=False):
    require(depth <= 16, "INVALID_FRAME")
    if type(value) is str:
        text(value, maximum=8 * 1024 * 1024)
        return unicodedata.normalize("NFC", value) if normalize else value
    if type(value) is dict:
        output = {}
        for key, child in value.items():
            key = text(key, maximum=256 * 1024)
            normalized = unicodedata.normalize("NFC", key) if normalize else key
            require(normalized not in output, "INVALID_FRAME")
            output[normalized] = _tree(child, depth + 1, normalize)
        return output
    if type(value) is list:
        return [_tree(child, depth + 1, normalize) for child in value]
    require(value is None or type(value) in (bool, int), "INVALID_FRAME")
    return value


def canonical(value):
    # Python's Unicode string sorting orders code points, as foundation does.
    # No float, secret-bearing field or platform newline conversion is involved.
    return json.dumps(_tree(value, normalize=True), ensure_ascii=False,
                      sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def wire_bytes(value):
    """Preserve observed text; canonical NFC is for hashes, not transport."""
    return json.dumps(_tree(value), ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


def _pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "INVALID_FRAME")
        result[key] = value
    return result


def _invalid_number(_):
    raise Rejected("INVALID_FRAME")


def decode(data, maximum=256 * 1024):
    require(type(data) is bytes and 0 < len(data) <= maximum, "INVALID_FRAME")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_pairs,
                           parse_float=_invalid_number, parse_constant=_invalid_number)
        _tree(value)
        require(type(value) is dict, "INVALID_FRAME")
        return value
    except (ValueError, UnicodeError, RecursionError):
        raise Rejected("INVALID_FRAME") from None


def _exact(stream, size):
    chunks = bytearray()
    while len(chunks) < size:
        chunk = stream.read(size - len(chunks))
        require(bool(chunk), "INVALID_FRAME")
        chunks.extend(chunk)
    return bytes(chunks)


def read_frame(stream, maximum=256 * 1024):
    size, = struct.unpack(">I", _exact(stream, 4))
    require(0 < size <= maximum, "INVALID_FRAME")
    return decode(_exact(stream, size), maximum)


def write_frame(stream, document, maximum=8 * 1024 * 1024):
    data = wire_bytes(document)
    require(0 < len(data) <= maximum, "RESOURCE_LIMIT")
    stream.write(struct.pack(">I", len(data)))
    stream.write(data)
    stream.flush()
