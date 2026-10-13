from ._util import _add_column
def migrate(c,ver):
 _add_column(c,'scheduled_tasks','execution_mode',"TEXT NOT NULL DEFAULT 'read_only'")
 _add_column(c,'owned_tasks','scheduled_run_id','INTEGER REFERENCES scheduled_task_runs(id) ON DELETE SET NULL')
 c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_owned_schedule ON owned_tasks(scheduled_run_id) WHERE scheduled_run_id IS NOT NULL')
