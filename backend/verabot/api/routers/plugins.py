"""插件 API。/api/mcp/* 在 P1 仍可用，但已弃用。"""
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ...services.plugins import service as plugins
from ...services.plugins.service import PluginError
from ..deps import current_user

router = APIRouter(tags=["plugins"])


class EnabledIn(BaseModel):
    enabled: bool


class ConsentIn(BaseModel):
    granted: bool


class CredentialIn(BaseModel):
    token: str = Field(min_length=1, max_length=512, repr=False)

    def __repr__(self) -> str:   # 不打印令牌
        return "CredentialIn(token=<redacted>)"


_LOOPBACK = {"127.0.0.1", "::1", "localhost"}


def _secure(request: Request) -> bool:
    """D4：令牌只经本机回环或 HTTPS 上传。不信任 X-Forwarded-* 头。"""
    host = request.client.host if request.client else ""
    return host in _LOOPBACK or request.url.scheme == "https"


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except PluginError as exc:
        detail = {"message": exc.message, "code": exc.code} if exc.code else exc.message
        raise HTTPException(exc.status, detail) from None


@router.get("/api/plugins/catalog")
def catalog(user=Depends(current_user)):
    return {"catalog": plugins.list_catalog(user["id"])}


@router.get("/api/plugins")
def installed(user=Depends(current_user)):
    return {"plugins": plugins.list_installed(user["id"])}


@router.get("/api/plugins/{plugin_id}")
def one(plugin_id: str, user=Depends(current_user)):
    return _call(plugins.get_plugin, user["id"], plugin_id)


@router.post("/api/plugins/{plugin_id}/install", status_code=201)
def install(plugin_id: str, user=Depends(current_user)):
    return _call(plugins.install, user["id"], plugin_id)


@router.delete("/api/plugins/{plugin_id}")
def uninstall(plugin_id: str, user=Depends(current_user)):
    return _call(plugins.uninstall, user["id"], plugin_id)


@router.patch("/api/plugins/{plugin_id}")
def patch_plugin(plugin_id: str, body: EnabledIn, user=Depends(current_user)):
    return _call(plugins.set_enabled, user["id"], plugin_id, body.enabled)


@router.post("/api/plugins/{plugin_id}/consent")
def consent(plugin_id: str, body: ConsentIn, user=Depends(current_user)):
    return _call(plugins.set_consent, user["id"], plugin_id, body.granted)


@router.get("/api/plugins/{plugin_id}/tools")
def tools(plugin_id: str, user=Depends(current_user)):
    return {"tools": _call(plugins.list_tools, user["id"], plugin_id)}


@router.post("/api/plugins/{plugin_id}/sync")
def sync(plugin_id: str, user=Depends(current_user)):
    return _call(plugins.sync, user["id"], plugin_id)


@router.put("/api/plugins/{plugin_id}/credential")
def put_credential(plugin_id: str, body: CredentialIn, request: Request, user=Depends(current_user)):
    """仅 auth_mode=bearer。校验格式与连通后加密保存；响应是 Plugin（不含令牌）。"""
    return _call(plugins.set_credential, user["id"], plugin_id, body.token, secure_transport=_secure(request))


@router.delete("/api/plugins/{plugin_id}/credential")
def delete_credential(plugin_id: str, user=Depends(current_user)):
    return _call(plugins.delete_credential, user["id"], plugin_id)


@router.post("/api/plugins/{plugin_id}/accept-tool-changes")
def accept_tool_changes(plugin_id: str, user=Depends(current_user)):
    """D7：接受这个插件所有定义已变化的工具。"""
    return _call(plugins.accept_tool_changes, user["id"], plugin_id)
