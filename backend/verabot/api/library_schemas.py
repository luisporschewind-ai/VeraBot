from pydantic import BaseModel

class LibraryMutationResult(BaseModel):
    ok: bool = True
