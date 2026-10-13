#!/usr/bin/env python3
"""Real socket checks for durable group protocol v2 using only the local fake provider."""
import asyncio
import json
import sys
from uuid import uuid4

import httpx

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8093"
PROTOCOL = {"X-VeraBot-Group-Protocol": "2"}


async def wait_for(client, group_path, *, wanted):
    for _ in range(120):
        snapshot = (await client.get(group_path + "/execution")).json()
        task = snapshot.get("task")
        if task and task["state"] in wanted:
            return snapshot
        await asyncio.sleep(0.1)
    raise AssertionError(f"execution did not reach {wanted}: {snapshot}")


async def read_events(client, path, after_id):
    events = []
    async with client.stream("GET", path + f"/events?after_id={after_id}") as response:
        assert response.status_code == 200, await response.aread()
        event_id, kind = None, None
        async for line in response.aiter_lines():
            if line.startswith("id: "):
                event_id = int(line[4:])
            elif line.startswith("event: "):
                kind = line[7:]
            elif line.startswith("data: "):
                events.append((kind, json.loads(line[6:])))
    return events


async def disconnect_after_first_event(client, path, after_id):
    async with client.stream("GET", path + f"/events?after_id={after_id}") as response:
        assert response.status_code == 200, await response.aread()
        async for line in response.aiter_lines():
            if line.startswith("data: "):
                json.loads(line[6:])
                return


async def main():
    async with httpx.AsyncClient(base_url=URL, timeout=35) as client:
        login = await client.post("/api/auth/login", json={"username": "group-demo", "password": "group-demo-123"})
        login.raise_for_status()
        client.headers["Authorization"] = "Bearer " + login.json()["token"]
        ids = [item["id"] for item in (await client.get("/api/bots")).json()["bots"][:3]]
        created = await client.post("/api/groups", headers=PROTOCOL,
                                   json={"name": "G3 HTTP 联调", "bot_ids": ids})
        assert created.status_code == 201, created.text
        group_id = created.json()["id"]
        path = f"/api/groups/{group_id}"
        legacy = await client.post(path + "/chat", json={"client_request_id": str(uuid4()), "message": "old"})
        assert legacy.status_code == 426, legacy.text
        assert (await client.get(path + "/messages")).status_code == 200
        print("PASS group creation without default member; legacy writes require protocol v2", flush=True)

        request = {"client_request_id": str(uuid4()), "message": "请帮我看看这份计划", "target_member_ids": [],
                   "everyone": False, "reply_to_message_id": None, "attachment_ids": []}
        accepted = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        assert accepted.status_code == 202, accepted.text
        duplicate = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        assert duplicate.status_code == 200 and duplicate.json()["input_id"] == accepted.json()["input_id"]
        receipt = await client.get(path + "/inputs/" + request["client_request_id"])
        assert receipt.status_code == 200 and receipt.json()["turn_id"] == accepted.json()["turn_id"]
        final = await wait_for(client, path, wanted={"completed"})
        events = await read_events(client, path, accepted.json()["event_cursor"])
        kinds = [kind for kind, _ in events]
        assert "route_decided" in kinds and "step_completed" in kinds
        assert final["task"]["state"] == "completed"
        print("PASS submit acknowledgement, duplicate UUID, socket-independent worker, persisted event replay", flush=True)

        request = {"client_request_id": str(uuid4()), "message": "帮我弄一下", "target_member_ids": [],
                   "everyone": False, "reply_to_message_id": None, "attachment_ids": []}
        accepted = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        assert accepted.status_code == 202, accepted.text
        waiting = await wait_for(client, path, wanted={"awaiting_user"})
        clarification = waiting["clarification"]
        assert clarification and clarification["owner_member_id"] is not None
        assert clarification["latest_question_message_id"] is not None
        answer = {"client_request_id": str(uuid4()), "message": "计划周末徒步，预算有限", "target_member_ids": [],
                  "everyone": False, "reply_to_message_id": None, "attachment_ids": [],
                  "expected_task_id": waiting["task"]["id"], "expected_version": waiting["task"]["version"],
                  "clarification_id": clarification["id"]}
        followup = await client.post(path + "/inputs", headers=PROTOCOL, json=answer)
        assert followup.status_code == 202, followup.text
        done = await wait_for(client, path, wanted={"completed"})
        assert done["task"]["owner_member_id"] == clarification["owner_member_id"]
        print("PASS dynamic Bot clarification, stable owner, user answer resumes the same task", flush=True)

        request = {"client_request_id": str(uuid4()), "message": "[consult] 评估这个方案", "target_member_ids": [],
                   "everyone": False, "reply_to_message_id": None, "attachment_ids": []}
        accepted = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        assert accepted.status_code == 202, accepted.text
        await disconnect_after_first_event(client, path, accepted.json()["event_cursor"])
        consulted = await wait_for(client, path, wanted={"completed"})
        events = await read_events(client, path, accepted.json()["event_cursor"])
        kinds = [kind for kind, _ in events]
        consult_events = [data for kind, data in events if kind == "handoff_scheduled" and data["payload"].get("kind") == "consult"]
        assert consult_events
        assert consulted["task"]["owner_member_id"] == consult_events[0]["payload"]["from_member_id"]
        print("PASS observer disconnect leaves worker running; consult returns to original owner and replays events", flush=True)

        request = {"client_request_id": str(uuid4()), "message": "[handoff] 做完这份方案", "target_member_ids": [],
                   "everyone": False, "reply_to_message_id": None, "attachment_ids": []}
        accepted = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        assert accepted.status_code == 202, accepted.text
        done = await wait_for(client, path, wanted={"completed"})
        events = await read_events(client, path, accepted.json()["event_cursor"])
        handoffs = [data for kind, data in events if kind == "handoff_scheduled"]
        assert handoffs and done["task"]["owner_member_id"] == handoffs[-1]["payload"]["to_member_id"]
        print("PASS structured handoff changes owner and ends with the receiving Bot", flush=True)

        request = {"client_request_id": str(uuid4()), "message": "帮我弄一下", "target_member_ids": [],
                   "everyone": False, "reply_to_message_id": None, "attachment_ids": []}
        waiting = await client.post(path + "/inputs", headers=PROTOCOL, json=request)
        waiting.raise_for_status()
        snapshot = await wait_for(client, path, wanted={"awaiting_user"})
        stopped = await client.post(path + f"/tasks/{snapshot['task']['id']}/stop", headers=PROTOCOL,
                                    json={"client_request_id": str(uuid4()), "expected_version": snapshot["task"]["version"]})
        assert stopped.status_code == 200 and stopped.json()["state"] == "stopped", stopped.text
        print("PASS explicit stop cancels a clarification that is waiting for user input", flush=True)


asyncio.run(main())
