"""MCP 风险确认策略（HITL）。注解推导见 sync.risk_for；本模块只决定「要不要弹确认卡片」。"""
from __future__ import annotations


def requires_confirmation(tool: dict) -> bool:
    """v1：所有非只读工具都要确认；只读工具仅当用户设 confirm_policy=always 时确认。

    发送 / 破坏性永远不能自动执行（没有配置能跳过）。
    """
    risk = tool.get("risk") or "destructive"
    if risk != "read":
        return True
    return (tool.get("confirm_policy") or "default") == "always"


def risk_label(risk: str) -> str:
    return {
        "read": "只读",
        "write": "写入",
        "send": "发送",
        "destructive": "破坏性",
    }.get(risk, risk)


def cross_server_warnings(read_servers: set[str], target_server: str) -> list[str]:
    """同一轮先读了 A 再向 B 写时，确认卡片提示「内容来自 A」。"""
    others = sorted(s for s in read_servers if s and s != target_server)
    if not others:
        return []
    joined = "、".join(others)
    return [f"本轮已读取来自「{joined}」的外部内容，请确认不会把其中内容发到「{target_server}」"]


def validate_confirm_policy(tool: dict, policy: str) -> str | None:
    """返回中文错误，或 None 表示可接受。只能更严格；发送 / 破坏性不能设成可自动执行。"""
    if policy in ("never", "auto", "once", "off", "false"):
        return "发送或破坏性操作必须每次确认，不能设为自动执行" if (tool.get("risk") or "") in (
            "send", "destructive", "write",
        ) else "不能关闭确认"
    if policy not in ("always", "default"):
        return "confirm_policy 只能是 always 或 default"
    return None
