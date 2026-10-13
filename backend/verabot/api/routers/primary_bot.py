from fastapi import APIRouter, Depends, HTTPException
from ..deps import current_user
from ..primary_bot_schemas import PrimaryBotPatch
from ...services import primary_bot
from ...services.scheduled_tasks.contracts import TaskError
router=APIRouter(prefix='/api/primary-bot',tags=['primary-bot'])
@router.get('')
def get(user=Depends(current_user)):return primary_bot.get(user['id'])
@router.patch('')
def update(body:PrimaryBotPatch,user=Depends(current_user)):
 try:return primary_bot.update(user['id'],body.model_dump(exclude_unset=True,exclude={'expected_version'}),body.expected_version)
 except TaskError as e:raise HTTPException(e.status,{'code':e.code,'message':e.message}) from e
