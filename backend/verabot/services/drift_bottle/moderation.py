"""Restricted administrator handling for Drift Bottle reports.

There is no public admin HTTP surface in the first version. The CLI in
`backend/scripts/drift_bottle_admin.py` opens an explicit database path and
calls this module; the administrator identity must be configured in
`VERABOT_DRIFT_BOTTLE_ADMINS`.
"""
from __future__ import annotations

from ...db import drift_bottle_store as store
from .contracts import BottleError

ACTIONS = ("keep", "hide", "restore")


def pending(c) -> list[dict]:
    return store.pending_reports(c)


def moderate(c, admin_id: int, report_id: int, action: str, reason: str, now: float,
             admins: set[int] | None = None) -> dict:
    if action not in ACTIONS:
        raise BottleError(422, "invalid_action", "只支持 keep / hide / restore")
    return store.moderate_tx(c, admin_id, report_id, action, reason, now, admins)
