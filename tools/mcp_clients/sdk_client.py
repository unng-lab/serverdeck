"""Independent official MCP Python SDK2 client; locked Windows test dependency."""
import asyncio
import logging
import os
import sys
from importlib.metadata import version

from common import configuration, controls, emit, failed


async def run():
    if version("mcp") != "2.0.0" or version("mcp-types") != "2.0.0":
        raise ValueError("ACTOR_SDK_VERSION")
    from mcp import Client, StdioServerParameters, stdio_client
    config, scanner = configuration()
    reader, writer = os.pipe()
    drain = scanner.drain(os.fdopen(reader, "rb"))
    try:
        with os.fdopen(writer, "w", encoding="utf-8") as diagnostics:
            server = StdioServerParameters(command=config["command"], args=config["args"])
            async with Client(stdio_client(server, errlog=diagnostics), read_timeout_seconds=45) as client:
                emit({"ready": True, "client": "official-sdk-2.0.0",
                      "protocolVersion": client.protocol_version}, scanner)
                iterator = iter(controls())
                # Parent control input is blocking; keep the actual SDK event
                # loop alive for native IO, notifications and cancellation.
                while (command := await asyncio.to_thread(lambda: next(iterator, None))) is not None:
                    method, params = command["method"], command.get("params", {})
                    if method == "tools/list":
                        result = await client.list_tools(cursor=params.get("cursor"), cache_mode="refresh")
                        payload = {"tools": [tool.model_dump(by_alias=True, mode="json", exclude_none=True)
                                              for tool in result.tools]}
                        if result.next_cursor is not None:
                            payload["nextCursor"] = result.next_cursor
                    elif method == "tools/call":
                        result = await client.call_tool(params["name"], arguments=params.get("arguments", {}))
                        payload = {"content": [item.model_dump(by_alias=True, mode="json", exclude_none=True)
                                               for item in result.content],
                                   "structuredContent": result.structured_content, "isError": result.is_error}
                    else:
                        await client.session.send_ping()
                        payload = {}
                    emit({"jsonrpc": "2.0", "id": command["id"], "result": payload}, scanner)
    finally:
        await asyncio.to_thread(drain.join, 2)
    if drain.is_alive() or scanner.failed:
        raise ValueError("ACTOR_SHUTDOWN")


if __name__ == "__main__":
    logging.disable(logging.CRITICAL)
    try:
        asyncio.run(run())
    except BaseException:
        sys.exit(failed())
