"""Isolated load-harness API, never import from production main.
Authentication is replaced only for an explicit disposable database environment.
"""
import os
from pathlib import Path
from fastapi import FastAPI,Header,HTTPException
if os.environ.get('VERABOT_TETRIS_LOAD_TEST')!='1':raise RuntimeError('test harness requires explicit isolated mode')
if 'tetris-load-' not in str(Path(os.environ['VERABOT_DB']).parent):raise RuntimeError('test harness refuses non-disposable DB')
from verabot.api.deps import current_user
from verabot.api.routers.tetris_sessions import router
app=FastAPI();app.include_router(router)
def test_user(x_test_user:int|None=Header(default=None)):
    if x_test_user is None or not 100<=x_test_user<116:raise HTTPException(401,'isolated test user required')
    return {'id':x_test_user}
app.dependency_overrides[current_user]=test_user
