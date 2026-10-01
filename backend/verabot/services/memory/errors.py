"""记忆业务错误（不依赖 FastAPI）。api 层把它映射为 HTTP：{"detail": {"message", "code", ...}}。"""


class MemoryServiceError(Exception):
    def __init__(self, status: int, code: str, message: str, **extra):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra

    def detail(self) -> dict:
        return {"message": self.message, "code": self.code, **self.extra}
