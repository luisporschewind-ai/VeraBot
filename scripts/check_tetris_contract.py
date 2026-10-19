#!/usr/bin/env python3
"""Check committed schemas, references and both expected fixture snapshots."""
import hashlib
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from verabot.services.tetris_sessions.contracts import Snapshot,Step,HandoffRequest,CommandRequest,FIXTURE_SHA256
from verabot.services.tetris_sessions.rules import restore

def check():
    schema=json.loads((ROOT/'docs/contracts/tetris-session-v1.schema.json').read_text())
    def references(node):
        if isinstance(node,dict):
            if '$ref' in node:
                reference=node['$ref']
                if not reference.startswith('#/$defs/') or reference.split('/')[-1] not in schema['$defs']:raise ValueError('unresolved schema reference')
            for item in node.values():references(item)
        elif isinstance(node,list):
            for item in node:references(item)
    references(schema)
    for model in (Snapshot,Step,HandoffRequest,CommandRequest):
        expected=model.model_json_schema();expected.pop('$defs',None)
        if schema['$defs'][model.__name__]!=expected:raise ValueError('schema drift: '+model.__name__)
    path=ROOT/'docs/contracts/tetris-v2-fixtures.json'
    fixtures=json.loads(path.read_text())
    if fixtures['ruleVersion']!='vera-tetris-2':raise ValueError('wrong fixture rule version')
    names=set()
    for case in fixtures['cases']:
        if case['name'] in names:raise ValueError('duplicate fixture')
        names.add(case['name'])
        restore(case['initial']);restore(case['expectedSnapshot'])
        for step in case['steps']:
            Step.model_validate(step)
            if len(step)!=1:raise ValueError('fixture step needs exactly one action or elapsed')
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    swift=(ROOT/'frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/TetrisContract.swift').read_text()
    if digest!=FIXTURE_SHA256 or digest not in swift:raise ValueError('build fixture hash drift')
    print(f'{len(names)} fixtures; schema references and snapshots valid; SHA256={hashlib.sha256(path.read_bytes()).hexdigest()}')
if __name__=='__main__':check()
