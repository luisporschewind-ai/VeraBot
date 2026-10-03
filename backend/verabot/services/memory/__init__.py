"""记忆服务（Memory service）门面：显式记忆的全部业务规则，不依赖 FastAPI / agents。

实现在 service.py；本文件只 re-export，保持 `from verabot.services import memory` 的原有用法不变。
对外：enabled_for / settings / recall / propose / confirm / reject / create / update / delete / clear /
clear_for_bot / list_memories / get_memory / mark_used / bot_counts。错误一律抛 MemoryServiceError（api 层映射 HTTP）。
审计（audit_log）只记 {memory_id, type, scope, bot_id, source, code, ...}，**从不记正文**；日志同样不写正文。
"""
from .errors import MemoryServiceError  # noqa: F401
from .recall import EMPTY, Recall  # noqa: F401
from .service import (  # noqa: F401
    LIVE,
    PENDING,
    STATUSES,
    bot_counts,
    clear,
    clear_for_bot,
    confirm,
    create,
    delete,
    enabled_for,
    get_memory,
    list_memories,
    mark_used,
    propose,
    public,
    r_user,
    recall,
    reject,
    set_enabled,
    settings,
    update,
)
