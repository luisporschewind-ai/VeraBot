"""落库 / 同步用的工具 trace 瘦身。

模型在本轮拿到的是完整工具结果（runtime 的 tool 消息）；messages.traces、回复事件与 SSE 里的 trace
只给客户端画卡片、给后续轮次做历史摘要，不需要原文：
- read_file：去掉 text，只留 filename / offset / length（本次实际读到的字数）/ next_offset / has_more /
  text_chars / text_status 等元数据，并标 text_omitted。
- 其他工具：result 里任何超过 TEXT_LIMIT 的字符串截到 TEXT_LIMIT 并接 TRUNCATED_MARK；
  原长度按点分路径记在 result["trace_truncated"]（如 {"content": 8123}）。
可重复调用：已瘦身的 trace 再跑一遍不变。
"""
TEXT_LIMIT = 2000
TRUNCATED_MARK = "…[truncated]"


def _cap(value, path: str, lengths: dict):
    if isinstance(value, str):
        if len(value) > TEXT_LIMIT + len(TRUNCATED_MARK):
            lengths[path] = len(value)
            return value[:TEXT_LIMIT] + TRUNCATED_MARK
        return value
    if isinstance(value, dict):
        return {k: _cap(v, f"{path}.{k}" if path else str(k), lengths) for k, v in value.items()}
    if isinstance(value, list):
        return [_cap(v, f"{path}.{i}" if path else str(i), lengths) for i, v in enumerate(value)]
    return value


def slim_result(name: str, result):
    if not isinstance(result, dict):
        return result
    if name == "read_file" and "text" in result:
        text = result["text"]
        result = {k: v for k, v in result.items() if k != "text"}
        result["length"] = len(text) if isinstance(text, str) else 0
        result["text_omitted"] = True
    lengths: dict = {}
    slim = _cap(result, "", lengths)
    if lengths:
        slim["trace_truncated"] = {**(result.get("trace_truncated") or {}), **lengths}
    return slim


def slim_trace(trace):
    if not isinstance(trace, dict) or "result" not in trace:
        return trace
    return {**trace, "result": slim_result(trace.get("name") or "", trace["result"])}


def slim_traces(traces):
    if not isinstance(traces, list):
        return traces
    return [slim_trace(t) for t in traces]
