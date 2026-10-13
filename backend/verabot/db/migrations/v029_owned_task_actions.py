from ._util import _add_column
def migrate(c,ver):
 for name,ddl in (('owned_task_id','INTEGER REFERENCES owned_tasks(id) ON DELETE SET NULL'),('owned_step_id','INTEGER REFERENCES owned_steps(id) ON DELETE SET NULL'),('owned_task_version','INTEGER'),('owned_resolution_at','TEXT'),('owned_result_enc','BLOB')):
  _add_column(c,'pending_actions',name,ddl)
