"""
Private Tools MCP Server

All tools require authentication of the user.
"""
import time

from geopy.geocoders import Nominatim
from mcp.server.fastmcp import FastMCP

def authenticate()

mcp = FastMCP("Private-Tools", json_response=True)
# Run from the repository root:
# uv run examples/snippets/servers/fastmcp_quickstart.py

# Run with streamable HTTP transport
if __name__ == "__main__":
    mcp.run(transport="streamable-http")
