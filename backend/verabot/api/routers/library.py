"""User-owned library endpoints; Bot tool access uses separate authorization."""
from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from ..deps import current_user
from ..library_schemas import LibraryMutationResult
from ...services import library
from ...services.attachments import repo
from ...core.config import ATTACHMENT_MAX_BYTES

router=APIRouter(prefix='/api/library',tags=['library'])

def run(fn,*args,**kwargs):
    try: return fn(*args,**kwargs)
    except (library.LibraryError,repo.AttachmentError) as error:
        raise HTTPException(error.status,dict(message=error.message,code=error.code)) from error

@router.get('/items')
def items(kind:str|None=None,bot_id:int|None=None,q:str=Query('',max_length=500),cursor:str|None=None,limit:int=Query(50,ge=1,le=100),user=Depends(current_user)):
    if kind not in (None,'file','image'): raise HTTPException(422,'无效资料类型')
    return run(library.catalog,user['id'],kind=kind,bot_id=bot_id,q=q,cursor=cursor,limit=limit)

@router.get('/changes')
def changes(after_revision:int=Query(0,ge=0),user=Depends(current_user)):
    return run(library.changes,user['id'],after_revision)

@router.post('/items',status_code=201)
def upload(file:UploadFile=File(...),bot_id:int|None=Form(None),idempotency_key:str=Header(alias='Idempotency-Key'),user=Depends(current_user)):
    data=file.file.read(ATTACHMENT_MAX_BYTES+1);file.file.close()
    return run(library.upload,user['id'],data,file.filename or 'file',file.content_type or '',idempotency_key,bot_id)

@router.get('/items/{item_id}')
def detail(item_id:str,user=Depends(current_user)): return run(library.get_item,user['id'],item_id)

@router.put('/items/{item_id}/bots/{bot_id}')
def link(item_id:str,bot_id:int,user=Depends(current_user)):
    run(library.link_bot,user['id'],item_id,bot_id);return LibraryMutationResult()

@router.delete('/items/{item_id}/bots/{bot_id}')
def unlink(item_id:str,bot_id:int,user=Depends(current_user)):
    run(library.unlink_bot,user['id'],item_id,bot_id);return LibraryMutationResult()

@router.delete('/items/{item_id}')
def delete(item_id:str,user=Depends(current_user)):
    run(library.delete_item,user['id'],item_id);return LibraryMutationResult()

def download(user,item_id,variant):
    row=run(library.content_row,user['id'],item_id)
    path=repo.file_path(row,variant)
    if path is None: raise HTTPException(410,dict(message='原件不可用',code='library_resource_missing'))
    return FileResponse(path,media_type=row['mime'] if variant=='content' else 'image/jpeg',filename=row.get('filename') if variant=='content' else None,headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','ETag':row['sha256']})

@router.get('/items/{item_id}/content')
def content(item_id:str,user=Depends(current_user)): return download(user,item_id,'content')

@router.get('/items/{item_id}/thumb')
def thumb(item_id:str,user=Depends(current_user)): return download(user,item_id,'thumb')
