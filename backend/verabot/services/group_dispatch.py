"""Group input boundary; persist first, classify later in the execution worker."""
from ..db import group_execution_store


def submit(user_id: int, group_id: int, request: dict):
    prior = group_execution_store.snapshot(user_id, group_id)
    task = group_execution_store.create_input(user_id, group_id, request)
    if prior is not None and (prior["id"] != task["id"] or prior["version"] != task["version"]):
        from . import group_worker
        group_worker.request_cancel(prior["id"])
    return task
