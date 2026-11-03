# Pinned MCP schema fixture

Source: [official MCP 2025-11-25 schema](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-11-25/schema.json).
The fixture was obtained during003 research, before implementation, and is reused
byte for byte. SHA256:
`1ffe4c5577974012f5fa02af14ea88df4b7146679df1abaaad497c8d9230ca8a`.

This is an offline unit fixture for Tool/ListToolsResult compatibility and local
JSON Schema validation. It neither runs an MCP client nor makes network requests.
The JSON Schema validator is a development dependency in
`tools/unit-requirements.txt`; it is not included in ServerDeck.exe.
