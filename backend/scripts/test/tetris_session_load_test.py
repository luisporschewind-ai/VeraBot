"""Ten-minute isolated API + worker load run; never migrates the configured live DB."""
import argparse
import asyncio
import json
import math
import os
from pathlib import Path
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
import httpx
from verabot.db.migrations.v038_tetris_sessions import migrate
from verabot.services.tetris_sessions import rules
class RoundEnded(Exception):pass
BACKEND=Path(__file__).resolve().parents[2]
def percentile(values,p=.95):
    return sorted(values)[max(0,math.ceil(len(values)*p)-1)] if values else None
def stop(process):
    if process.poll() is not None:return
    # Graceful stop of the owner lets it drain/close its planner pool. Killing
    # the whole group here would manufacture BrokenProcessPool at test teardown.
    try:process.send_signal(signal.SIGTERM)
    except ProcessLookupError:return
    try:process.wait(timeout=8)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
async def run(duration,output,users):
    output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='verabot-tetris-load-') as folder:
        database=Path(folder)/'load.db';c=sqlite3.connect(database)
        c.executescript('CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER);')
        migrate(c,37)
        for uid in range(100,100+users):c.execute('INSERT INTO users VALUES(?)',(uid,));c.execute('INSERT INTO bots VALUES(?,?)',(uid,uid))
        c.commit();c.close()
        env={**os.environ,'VERABOT_DB':str(database),'VERABOT_DATA_DIR':folder,'VERABOT_JWT_SECRET':'isolated-load-only','VERABOT_TETRIS_LOAD_TEST':'1','DEEPSEEK_API_KEY':'','OPENAI_API_KEY':''}
        with socket.socket() as listener:listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
        logs=[open(output/'api.log','w'),open(output/'worker.log','w')]
        processes=[]
        try:
            processes.append(subprocess.Popen([sys.executable,'-m','uvicorn','scripts.test.tetris_load_api:app','--host','127.0.0.1','--port',str(port),'--no-access-log'],cwd=BACKEND,env=env,stdout=logs[0],stderr=subprocess.STDOUT,start_new_session=True))
            processes.append(subprocess.Popen([sys.executable,'-m','verabot.services.tetris_sessions'],cwd=BACKEND,env=env,stdout=logs[1],stderr=subprocess.STDOUT,start_new_session=True))
            async with httpx.AsyncClient(base_url=f'http://127.0.0.1:{port}',timeout=5) as client:
                for _ in range(100):
                    try:
                        ready=await client.get('/api/games/tetris/sessions/capabilities',headers={'X-Test-User':'100'})
                        if ready.status_code==200 and ready.json()['workerReady']:break
                    except httpx.HTTPError:pass
                    await asyncio.sleep(.1)
                else:raise RuntimeError('isolated services did not become ready')
                clients={uid:str(uuid4()) for uid in range(100,100+users)}
                states={};latencies=[];failures=[];reclaims=[];new_rounds=0;conflicts=0;probes=[];cpu=[]
                prefix='/api/games/tetris/sessions'
                async def request(uid,method,path,body=None):
                    start=time.perf_counter()
                    result=await client.request(method,path,headers={'X-Test-User':str(uid)},json=body)
                    latencies.append((time.perf_counter()-start)*1000)
                    return result
                async def create(uid):
                    nonlocal new_rounds
                    game=rules.new(uid);rules.apply(game,'start')
                    body=dict(requestID=str(uuid4()),clientID=clients[uid],expectedVersion=0,expectedEpoch=0,botID=uid,snapshot=rules.snapshot(game))
                    result=await request(uid,'POST',prefix,body)
                    if result.status_code!=200:raise RuntimeError(f'create failed:{result.status_code}')
                    new_rounds+=1;return result.json()['session']
                for uid in clients:states[uid]=await create(uid)
                async def command(uid,kind,**extra):
                    nonlocal conflicts
                    for _ in range(8):
                        state=(await request(uid,'GET',prefix+'/'+states[uid]['id'])).json()
                        if state['runState']=='over':raise RoundEnded()
                        body=dict(requestID=str(uuid4()),clientID=clients[uid],expectedVersion=state['version'],expectedEpoch=state['controlEpoch'],command=kind,**extra)
                        result=await request(uid,'POST',prefix+'/'+state['id']+'/commands',body)
                        if result.status_code==409:conflicts+=1;continue
                        if result.status_code!=200:raise RuntimeError(f'command {kind} failed:{result.status_code}')
                        states[uid]=result.json()['session'];return result.json()
                    raise RuntimeError(f"control commands starved: {result.text}; state={state['runState']}; version={state['version']}")
                started=time.monotonic();next_control=started+5;next_probe=started
                while time.monotonic()-started<duration:
                    cycle=time.monotonic()
                    results=await asyncio.gather(*(request(uid,'GET',prefix+'/'+states[uid]['id']) for uid in clients))
                    for uid,result in zip(clients,results):
                        if result.status_code!=200:failures.append(result.status_code);continue
                        states[uid]=result.json()
                        if states[uid]['runState']=='over':states[uid]=await create(uid)
                    if time.monotonic()>=next_control:
                        uid=100+int((next_control-started)//5)%users
                        try:
                            await command(uid,'pauseBot');await command(uid,'resumeBot')
                            start=time.monotonic();pending=await command(uid,'reclaim')
                            while pending['status']=='pending':
                                await asyncio.sleep(.02)
                                pending=(await request(uid,'GET',prefix+'/operations/'+pending['requestID'])).json()
                                if time.monotonic()-start>5:raise RuntimeError('reclaim exceeded five seconds')
                            reclaims.append((time.monotonic()-start)*1000);states[uid]=pending['session']
                            if states[uid]['runState']!='over':await command(uid,'handoff',botID=uid,snapshot=states[uid]['latestSnapshot'])
                            else:states[uid]=await create(uid)
                        except RoundEnded:
                            # Natural top-out may race a control tap. It is a terminal
                            # result, not eight retries of an impossible command.
                            states[uid]=await create(uid)
                        next_control+=5
                    if time.monotonic()>=next_probe:
                        probe=sqlite3.connect(database,timeout=5);start=time.perf_counter();probe.execute('BEGIN IMMEDIATE');probes.append((time.perf_counter()-start)*1000);probe.rollback();probe.close()
                        value=subprocess.check_output(['ps','-p',str(processes[1].pid),'-o','%cpu='],text=True).strip()
                        if value:cpu.append(float(value))
                        next_probe+=1
                    if any(process.poll() is not None for process in processes):raise RuntimeError('isolated service exited during load')
                    await asyncio.sleep(max(0,.25-(time.monotonic()-cycle)))
                elapsed=time.monotonic()-started
            for process in processes:stop(process)
            for log in logs:log.flush()
            ticks=[]
            for line in (output/'worker.log').read_text().splitlines():
                try:item=json.loads(line)
                except ValueError:continue
                if item.get('event')=='tetris_tick':ticks.append(item)
            samples=[value for item in ticks for value in item.get('latenessMs',[])]
            c=sqlite3.connect(database)
            integrity=c.execute('PRAGMA integrity_check').fetchone()[0];c.close()
            summary=dict(durationSeconds=round(elapsed,2),users=users,startedRounds=new_rounds,pollIntervalMs=250,apiRequests=len(latencies),apiP95Ms=percentile(latencies),workerSamples=len(samples),workerLatenessP95Ms=percentile(samples),workerErrors=sum(item['errors'] for item in ticks),workerRejected=sum(item['rejected'] for item in ticks),maxPlanningQueue=max((item.get('planningQueue',0) for item in ticks),default=0),controlConflicts=conflicts,reclaims=len(reclaims),reclaimP95Ms=percentile(reclaims),sqliteProbeWaitP95Ms=percentile(probes),workerMainCPUMaxPercent=max(cpu,default=0),httpFailures=failures,integrity=integrity)
            summary['pass']=bool(samples) and summary['workerLatenessP95Ms']<=100 and not failures and not summary['workerErrors'] and integrity=='ok'
            (output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2),flush=True)
            return 0 if summary['pass'] else 1
        except Exception as error:
            (output/'failure.json').write_text(json.dumps(dict(error=type(error).__name__,detail=str(error),elapsedSeconds=round(time.monotonic()-started,2) if 'started' in locals() else None),indent=2)+'\n')
            raise
        finally:
            for process in processes:stop(process)
            for log in logs:log.close()
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--users',type=int,choices=range(1,17),default=16);parser.add_argument('--duration',type=int,default=600);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    raise SystemExit(asyncio.run(run(args.duration,args.output,args.users)))
