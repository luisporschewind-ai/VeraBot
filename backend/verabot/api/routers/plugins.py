"""插件 API。/api/mcp/* 在 P1 仍可用，但已弃用。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ...services.plugins import service as plugins
from ...services.plugins.service import PluginError
from ..deps import current_user

router = APIRouter(tags=["plugins"])


class EnabledIn(BaseModel):
    enabled: bool


class ConsentIn(BaseModel):
    granted: bool


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except PluginError as exc:
        raise HTTPException(exc.status, exc.message) from exc


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
