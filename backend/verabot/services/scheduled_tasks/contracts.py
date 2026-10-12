from dataclasses import dataclass, field

@dataclass
class ExecutionResult:
    state: str = 'succeeded'
    text: str = ''
    error_code: str | None = None
    error_summary: str | None = None
    usage: dict = field(default_factory=dict)
    usage_unknown: bool = False
    trace_summary: list = field(default_factory=list)

class TaskError(ValueError):
    def __init__(self, code: str, message: str, status: int = 400):
        self.code, self.message, self.status = code, message, status
        super().__init__(message)
