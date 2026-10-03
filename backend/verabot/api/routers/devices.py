"""设备注册。R1 不接收真实推送，只记下这台设备会自己排本地提醒。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ...services.notify import devices
from ..deps import current_user

router = APIRouter(tags=["devices"])


class DeviceIn(BaseModel):
    device_id: str
    platform: str = "ios"
    apns_token: str | None = None
    apns_env: str | None = None
    app_version: str | None = None
    os_version: str | None = None
    timezone: str | None = None
    local_reminders: bool = True


@router.post("/api/devices")
def register_device(body: DeviceIn, user=Depends(current_user)):
    try:
        return devices.register(user["id"], body.model_dump())
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


@router.delete("/api/devices/{device_id}")
def delete_device(device_id: str, user=Depends(current_user)):
    devices.unregister(user["id"], device_id)
    return {"ok": True}
