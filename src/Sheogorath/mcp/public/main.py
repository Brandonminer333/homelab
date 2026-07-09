"""
Public Tools MCP Server

All tools are free to use by AI regartless of request auth.
"""
import os
from datetime import datetime

import pandas as pd
from dotenv import load_dotenv
from pydantic import BaseModel
from mcp.server.fastmcp import FastMCP

from weather.weather import get_weather

number = BaseModel(
    name="number_input",
    description="A number input",
    type="number",
    required=True,
)

# Create an MCP server
mcp = FastMCP("Public-Tools", json_response=True)

# Calculator tools
@mcp.tool()
def add(a: number, b: number) -> number:
    """Add two numbers"""
    return a + b

@mcp.tool()
def subtract(a: number, b: number) -> number:
    """Subtract two numbers"""
    return a - b

@mcp.tool()
def multiply(a: number, b: number) -> number:
    """Multiply two numbers"""
    return a * b

@mcp.tool()
def divide(a: number, b: number) -> number:
    """Divide two numbers"""
    return a / b


@mcp.tool()
def power(a: number, b: number) -> number:
    """Raise a number to the power of another number"""
    return a ** b


# Datetime tools
@mcp.tool()
def time() -> str:
    """Get the current time"""
    return datetime.now().strftime("%H:%M:%S")


@mcp.tool()
def date() -> str:
    """Get the current date"""
    return datetime.now().strftime("%Y-%m-%d")


@mcp.tool()
def day_of_week() -> str:
    """Get the current day"""
    return datetime.now().strftime("%A")


# Weather tools
@mcp.tool()
def weather(city: str) -> str:
    """Get the weather for a city"""
    return get_weather(city)

# Run from the repository root:
# uv run examples/snippets/servers/fastmcp_quickstart.py

# Run with streamable HTTP transport
if __name__ == "__main__":
    mcp.run(transport="streamable-http")
