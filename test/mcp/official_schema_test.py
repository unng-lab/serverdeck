"""Offline unit validation against the pinned official MCP JSON Schema."""
import hashlib
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "test/fixtures/mcp-2025-11-25-schema.json"


class OfficialToolSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        data = SCHEMA.read_bytes()
        if hashlib.sha256(data).hexdigest() != "1ffe4c5577974012f5fa02af14ea88df4b7146679df1abaaad497c8d9230ca8a":
            raise AssertionError("Pinned official MCP schema identity changed")
        cls.official = json.loads(data)
        cls.registry = json.loads((ROOT / "assets/mcp/tools.json").read_bytes())

    def test_all_twenty_one_tool_definitions_and_tools_list(self):
        tools = self.registry["tools"]
        self.assertEqual(len(tools), 21)
        self.assertEqual(len({tool["name"] for tool in tools}), 21)
        schema = {**self.official, "$ref": "#/$defs/Tool"}
        validator = Draft202012Validator(schema)
        for tool in tools:
            with self.subTest(name=tool["name"]):
                validator.validate(tool)
                Draft202012Validator.check_schema(tool["inputSchema"])
                Draft202012Validator.check_schema(tool["outputSchema"])
                self.assertEqual(tool["inputSchema"]["type"], "object")
                self.assertEqual(tool["outputSchema"]["type"], "object")
        Draft202012Validator({**self.official, "$ref": "#/$defs/ListToolsResult"}).validate({"tools": tools})

    def test_runtime_registry_matches_specification(self):
        self.assertEqual((ROOT / "assets/mcp/tools.json").read_bytes(),
                         (ROOT / "specs/003-ssh-mcp/contracts/mcp-tools.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
