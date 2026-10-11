"""Group management rules. No model execution or private-history access."""
from ..db import group_store
from ..db.group_types import Group, GroupChatInput, GroupMember, GroupTurn

def require_group(user_id: int, group_id: int) -> Group:
    return group_store.get_group(user_id, group_id)

def speakers(user_id: int, group: Group, request: GroupChatInput) -> list[GroupMember]:
    current = require_group(user_id, group["id"])
    active = [m for m in current["members"] if m["available"]]
    if request.get("mode", "single") == "round": return active
    target = request.get("target_bot_id") or current["default_bot_id"]
    selected = [m for m in active if m["bot_id"] == target]
    if not selected: raise group_store.GroupStoreError(422, "invalid_member", "回应者不可用")
    return selected

def request_stop(user_id: int, group_id: int, turn_id: int) -> GroupTurn:
    turn = group_store.request_stop(user_id, group_id, turn_id)
    from ..agents.group_runtime import signal_stop
    signal_stop(user_id,group_id,turn_id)
    return turn
