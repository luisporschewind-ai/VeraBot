"""可插拔工具注册表 (Tool Registry)。导入即注册。"""
from .registry import REGISTRY, ToolContext, TurnState, run_tool  # noqa: F401
from . import reminder, weather  # noqa: F401  注册内置工具
from ..agents import delegation  # noqa: F401,E402  注册 ask_bot（多 Agent 委派工具，注册顺序与 v0.1 相同）
