"""Only server-curated read capabilities may run unattended."""
import json
from ... import db
from ...agents.tool_router import schemas_for
from ...db import mcp_store
from ..mcp import catalog, policy as mcp_policy, service as mcp
from .contracts import TaskError

BUILTINS=frozenset({'get_weather','list_reminders'})

def snapshot_tools(user_id,bot):
    accepted={name:'builtin' for name in BUILTINS if name in (bot.get('allowed_tools') or [])}
    for tool, server in mcp.connected_tool_rows(user_id):
        if tool['full_name'] not in (bot.get('allowed_tools') or []): continue
        if tool.get('mcp_name') not in catalog.READ_ONLY_TOOLS.get(server.get('catalog_id') or '',frozenset()): continue
        if tool.get('risk')!='read' or mcp_policy.requires_confirmation(tool): continue
        if tool.get('status')!='active' or tool.get('accepted_hash') != tool.get('def_hash'): continue
        accepted[tool['full_name']]=tool.get('def_hash') or ''
    return accepted

def allowed_tools(user_id,bot,snapshot):
    previous=json.loads(snapshot.get('authorized_tools_json') or '{}')
    current=snapshot_tools(user_id,bot)
    names={name for name,hashed in previous.items() if current.get(name)==hashed}
    return [t for t in schemas_for(bot,0,False,user_id) if t['function']['name'] in names]

def require_allowed(ctx,name):
    bot=db.get_bot(ctx.user_id,ctx.bot['id'])
    if not bot:
        raise TaskError('bot_deleted','负责 Bot 已删除')
    previous=ctx.scheduled_authorization or {}
    current=snapshot_tools(ctx.user_id,bot)
    if name not in previous or name not in current or previous[name]!=current[name]:
        raise TaskError('permission_revoked','该能力未获准后台执行')
