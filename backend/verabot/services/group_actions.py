"""Validate one explicit in-group collaboration action and plan the next member step."""
import hashlib

from ..db import group_execution_store

ALLOWED = {"completed", "consult", "handoff", "await_user"}


def validate(user_id: int, group: dict, task: dict, step: dict, raw_action: dict | None) -> dict:
    raw = raw_action or {"kind": "completed"}
    if not isinstance(raw, dict) or raw.get("kind") not in ALLOWED:
        raise ValueError("无效的协作动作")
    kind = raw["kind"]
    target = raw.get("target_member_id")
    members = {m["id"]: m for m in group.get("members", []) if m.get("available")}
    if kind in ("consult", "handoff"):
        if type(target) is not int or target not in members:
            raise ValueError("协作目标不是当前群的可用成员")
        if target == step.get("member_id"):
            raise ValueError("协作目标必须是另一位群成员")
    elif target is not None:
        raise ValueError("完成或追问动作不能包含协作目标")
    goal = raw.get("goal", "")
    result = raw.get("result", "")
    missing = raw.get("missing_information", [])
    if not isinstance(goal, str) or len(goal) > 2000 or not isinstance(result, str) or len(result) > 4000:
        raise ValueError("协作目标或结果格式无效")
    if not isinstance(missing, list) or any(not isinstance(item, str) for item in missing):
        raise ValueError("缺失信息格式无效")
    if kind == "await_user" and (not result.strip() or not missing):
        raise ValueError("等待用户的动作必须包含真实追问和缺失信息")
    criteria = raw.get("completion_criteria", "")
    if not isinstance(criteria,str) or len(criteria)>2000:
        raise ValueError("完成条件格式无效")
    if raw.get("issue_key") is not None and not isinstance(raw["issue_key"],str):
        raise ValueError("修改问题标识无效")
    context_ids = raw.get("context_message_ids", [])
    attachment_ids = raw.get("attachment_ids", [])
    if not isinstance(context_ids, list) or any(type(mid) is not int for mid in context_ids):
        raise ValueError("群消息引用无效")
    if not isinstance(attachment_ids, list) or any(not isinstance(aid, str) for aid in attachment_ids):
        raise ValueError("附件引用无效")
    if not group_execution_store.validate_action_references(user_id, group["id"], context_ids, attachment_ids):
        raise ValueError("协作引用不属于当前群")
    return {"kind": kind, "target_member_id": target, "goal": goal or task.get("goal", ""),
            "result": result, "context_message_ids": context_ids, "attachment_ids": attachment_ids,
            "completion_criteria": raw.get("completion_criteria", ""),
            "issue_key": raw.get("issue_key"), "missing_information": missing}


def next_steps(task: dict, step: dict, action: dict) -> list[dict]:
    """Carry the validated contract and bounded consultation return stack."""
    data = step.get("input", {})
    issue_key = action.get("issue_key") or step.get("issue_key") or data.get("issue_key") or f"task:{task['id']}:root"
    stack = list(data.get("consult_stack", []))
    # Backward compatibility with already persisted v2 single-return steps.
    if not stack and step.get("consult_return_step_id") is not None:
        stack = [{"member_id": task.get("owner_member_id"), "goal": task.get("goal", ""),
                  "step_id": step["consult_return_step_id"], "completion_criteria": ""}]
    contract = {"goal": action.get("goal") or data.get("goal") or task.get("goal", ""),
                "result": action.get("result", ""), "context_message_ids": action.get("context_message_ids", []),
                "attachment_ids": action.get("attachment_ids", []),
                "completion_criteria": action.get("completion_criteria", ""), "issue_key": issue_key}
    kind = action["kind"]
    if kind == "consult":
        # Provider-supplied action IDs must not reset the same consultation's return limit.
        issue_key = f"task:{task['id']}:consult:" + hashlib.sha256(
            (str(action['target_member_id']) + ":" + contract["goal"].strip().casefold()).encode()).hexdigest()[:24]
        contract["issue_key"] = issue_key
        stack.append({"member_id": step["member_id"], "goal": data.get("goal") or task.get("goal", ""),
                      "step_id": step["id"], "completion_criteria": data.get("completion_criteria", "")})
    if kind in ("consult", "handoff"):
        return [{**contract, "member_id": action["target_member_id"], "action": kind,
                 "consult_stack": stack, "consult_return_step_id": stack[-1]["step_id"] if stack else None}]
    if kind == "completed" and stack:
        frame = stack.pop()
        return [{**contract, "member_id": frame["member_id"], "goal": frame["goal"],
                 "completion_criteria": frame.get("completion_criteria", ""), "action": "consult_return",
                 "consult_stack": stack, "consult_return_step_id": stack[-1]["step_id"] if stack else None}]
    return []


def within_call_limit(call_count: int, limit: int = 6) -> bool:
    return call_count < limit


def may_return_for_issue(return_count: int) -> bool:
    return return_count < 1
