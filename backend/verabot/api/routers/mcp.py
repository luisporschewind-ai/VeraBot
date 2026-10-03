"""MCP 服务器与工具 API。OAuth 不在 M1。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ... import db
from ...db import mcp_store
from ...services.mcp import service as mcp
from ..deps import current_user

router = APIRouter(tags=["mcp"])


class ServerIn(BaseModel):
    catalog_id: str = Field(min_length=1, max_length=64)


class ServerPatch(BaseModel):
    enabled: bool


def _require(user_id: int, server_id: int) -> dict:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise HTTPException(404, "未找到该 MCP 服务")
    return row


@router.get("/api/mcp/catalog")
def catalog(user=Depends(current_user)):
    return {"catalog": mcp.public_catalog()}


@router.get("/api/mcp/servers")
def servers(user=Depends(current_user)):
    return {"servers": mcp.ensure_servers(user["id"])}


@router.post("/api/mcp/servers", status_code=201)
def add_server(body: ServerIn, user=Depends(current_user)):
    from ...services.mcp import catalog as cat
    spec = cat.by_id(body.catalog_id)
    if spec is None:
        raise HTTPException(422, "未知的 MCP 服务")
    if not spec["url"]:
        raise HTTPException(422, "尚未配置 MCP 服务地址")
    existing = mcp_store.get_server_by_slug(user["id"], spec["slug"])
    if existing:
        raise HTTPException(409, "已经添加过这个服务")
    mcp.ensure_servers(user["id"])
    row = mcp_store.get_server_by_slug(user["id"], spec["slug"])
    return mcp.public_server(row)


@router.patch("/api/mcp/servers/{server_id}")
def patch_server(server_id: int, body: ServerPatch, user=Depends(current_user)):
    _require(user["id"], server_id)
    return mcp.set_enabled(user["id"], server_id, body.enabled)


@router.delete("/api/mcp/servers/{server_id}")
def delete_server(server_id: int, user=Depends(current_user)):
    if not mcp.remove_server(user["id"], server_id):
        raise HTTPException(404, "未找到该 MCP 服务")
    return {"ok": True}


@router.post("/api/mcp/servers/{server_id}/sync")
def sync_server(server_id: int, user=Depends(current_user)):
    row = _require(user["id"], server_id)
    if row["status"] == "disabled":
        raise HTTPException(409, "服务已停用，先启用再刷新工具")
    return mcp.sync_server(user["id"], server_id)


@router.get("/api/mcp/servers/{server_id}/tools")
def server_tools(server_id: int, user=Depends(current_user)):
    _require(user["id"], server_id)
    return {"tools": [mcp.public_tool(t) for t in mcp_store.list_tools(user["id"], server_id)]}


@router.post("/api/mcp/tools/{tool_id}/accept-change")
def accept_change(tool_id: int, user=Depends(current_user)):
    row = mcp_store.accept_change(user["id"], tool_id)
    if row is None:
        raise HTTPException(404, "没有待接受的工具变更")
    db.audit(user["id"], None, "mcp_tool_change_accepted", {"tool_id": tool_id, "full_name": row["full_name"]})
    return mcp.public_tool(row)
